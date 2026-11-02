package main

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

// fakeOwner is the owner host: a control API and the Strata backend.
type fakeOwner struct {
	mu      sync.Mutex
	unit    string // running unit, "" when stopped
	healthy bool
	busy    bool
	starts  atomic.Int32
	stops   atomic.Int32
	// startedBy reports the code for /v1/start when a unit runs already.
	control, backend *httptest.Server
	sse              chan struct{}
}

func newFakeOwner(t *testing.T) *fakeOwner {
	o := &fakeOwner{sse: make(chan struct{})}
	cm := http.NewServeMux()
	cm.HandleFunc("GET /v1/status", func(w http.ResponseWriter, r *http.Request) {
		o.mu.Lock()
		defer o.mu.Unlock()
		s := controlStatus{State: "inactive", Healthy: o.healthy, Busy: o.busy}
		if o.unit != "" {
			u := o.unit
			s.Unit, s.State = &u, "active"
		}
		writeJSON(w, 200, s)
	})
	cm.HandleFunc("POST /v1/start", func(w http.ResponseWriter, r *http.Request) {
		o.mu.Lock()
		defer o.mu.Unlock()
		if o.unit != "" {
			writeJSON(w, 200, map[string]any{"started": false, "unit": o.unit})
			return
		}
		if o.busy {
			writeJSON(w, 409, map[string]any{"error": "busy"})
			return
		}
		o.starts.Add(1)
		o.unit = "strata-headless-iq3-s.service"
		go func() { // becomes healthy shortly after the start
			time.Sleep(30 * time.Millisecond)
			o.mu.Lock()
			o.healthy = true
			o.mu.Unlock()
		}()
		writeJSON(w, 202, map[string]any{"started": true, "unit": o.unit})
	})
	cm.HandleFunc("POST /v1/stop", func(w http.ResponseWriter, r *http.Request) {
		o.mu.Lock()
		defer o.mu.Unlock()
		o.stops.Add(1)
		o.unit, o.healthy = "", false
		writeJSON(w, 202, map[string]any{"stopped": true})
	})
	o.control = httptest.NewServer(cm)
	bm := http.NewServeMux()
	bm.HandleFunc("GET /health", func(w http.ResponseWriter, r *http.Request) {
		o.mu.Lock()
		defer o.mu.Unlock()
		if !o.healthy {
			w.WriteHeader(503)
			return
		}
		io.WriteString(w, "ok")
	})
	bm.HandleFunc("/v1/chat/completions", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "answer from %s", r.Header.Get("Authorization"))
	})
	bm.HandleFunc("/v1/stream", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/event-stream")
		io.WriteString(w, "data: 1\n\n")
		w.(http.Flusher).Flush()
		<-o.sse
		io.WriteString(w, "data: 2\n\n")
	})
	o.backend = httptest.NewServer(bm)
	t.Cleanup(func() { o.control.Close(); o.backend.Close() })
	return o
}

func (o *fakeOwner) set(unit string, healthy, busy bool) {
	o.mu.Lock()
	o.unit, o.healthy, o.busy = unit, healthy, busy
	o.mu.Unlock()
}

type clock struct {
	mu sync.Mutex
	t  time.Time
}

func (c *clock) now() time.Time { c.mu.Lock(); defer c.mu.Unlock(); return c.t }
func (c *clock) add(d time.Duration) {
	c.mu.Lock()
	c.t = c.t.Add(d)
	c.mu.Unlock()
}

func newTestGate(t *testing.T, o *fakeOwner) (*gate, *httptest.Server) {
	g, err := newGate(gateConfig{
		Listen: "unused", BackendURL: o.backend.URL, ControlURL: o.control.URL,
		IdleTimeoutSec: 1800, WakeTimeoutSec: 2, StartTimeoutSec: 2,
	})
	if err != nil {
		t.Fatal(err)
	}
	g.pollEvery, g.healthTTL = 5*time.Millisecond, 0
	srv := httptest.NewServer(g)
	t.Cleanup(srv.Close)
	return g, srv
}

func post(t *testing.T, url string) (int, string) {
	req, _ := http.NewRequest("POST", url, strings.NewReader(`{}`))
	req.Header.Set("Authorization", "Bearer k")
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	b, _ := io.ReadAll(resp.Body)
	return resp.StatusCode, string(b)
}

func TestRunningIsProxied(t *testing.T) {
	o := newFakeOwner(t)
	o.set("strata-headless-iq3-s.service", true, false)
	_, srv := newTestGate(t, o)
	code, body := post(t, srv.URL+"/v1/chat/completions")
	if code != 200 || body != "answer from Bearer k" || o.starts.Load() != 0 {
		t.Fatalf("%d %q starts=%d", code, body, o.starts.Load())
	}
}

func TestStoppedGetDoesNotStart(t *testing.T) {
	o := newFakeOwner(t)
	_, srv := newTestGate(t, o)
	resp, err := http.Get(srv.URL + "/v1/models")
	if err != nil {
		t.Fatal(err)
	}
	b, _ := io.ReadAll(resp.Body)
	resp.Body.Close()
	if resp.StatusCode != 503 || !strings.Contains(string(b), "send a POST") || o.starts.Load() != 0 {
		t.Fatalf("%d %s starts=%d", resp.StatusCode, b, o.starts.Load())
	}
}

func TestStoppedPostStartsAndProxies(t *testing.T) {
	o := newFakeOwner(t)
	g, srv := newTestGate(t, o)
	code, body := post(t, srv.URL+"/v1/chat/completions")
	if code != 200 || body != "answer from Bearer k" || o.starts.Load() != 1 {
		t.Fatalf("%d %q starts=%d", code, body, o.starts.Load())
	}
	if g.autoUnit != "strata-headless-iq3-s.service" {
		t.Fatalf("autoUnit %q", g.autoUnit)
	}
}

func TestBusyDoesNotStart(t *testing.T) {
	o := newFakeOwner(t)
	o.set("", false, true)
	_, srv := newTestGate(t, o)
	code, body := post(t, srv.URL+"/v1/chat/completions")
	if code != 503 || !strings.Contains(body, "desktop is in use") || o.starts.Load() != 0 {
		t.Fatalf("%d %q starts=%d", code, body, o.starts.Load())
	}
}

func TestConcurrentPostsStartOnce(t *testing.T) {
	o := newFakeOwner(t)
	_, srv := newTestGate(t, o)
	var wg sync.WaitGroup
	codes := make([]int, 4)
	for i := range codes {
		wg.Add(1)
		go func() {
			defer wg.Done()
			codes[i], _ = post(t, srv.URL+"/v1/chat/completions")
		}()
	}
	wg.Wait()
	for _, c := range codes {
		if c != 200 {
			t.Fatalf("codes %v", codes)
		}
	}
	if o.starts.Load() != 1 {
		t.Fatalf("starts=%d", o.starts.Load())
	}
}

func TestWakeOnLAN(t *testing.T) {
	o := newFakeOwner(t)
	controlURL := o.control.URL
	o.control.Close() // owner is off
	g, err := newGate(gateConfig{BackendURL: o.backend.URL, ControlURL: controlURL,
		WOL: &wolConfig{MAC: "a8:a1:59:d6:46:8e", Broadcast: "192.0.2.255:9"}, WakeTimeoutSec: 0, StartTimeoutSec: 1})
	if err != nil {
		t.Fatal(err)
	}
	var sent atomic.Int32
	g.sendWOL = func(mac, bc string) error { sent.Add(1); return nil }
	g.pollEvery = time.Millisecond
	if e := g.bringUp(); e == nil || !strings.Contains(e.message, "did not wake up") || sent.Load() != 1 {
		t.Fatalf("%v sent=%d", e, sent.Load())
	}
}

func TestIdleStopsOnlyAutoStarted(t *testing.T) {
	o := newFakeOwner(t)
	g, srv := newTestGate(t, o)
	c := &clock{t: time.Unix(1000, 0)}
	g.now = c.now
	// Manually started: never stopped by the gate.
	o.set("strata-headless-iq3-s.service", true, false)
	post(t, srv.URL+"/v1/chat/completions")
	c.add(time.Hour)
	g.idleCheck()
	if o.stops.Load() != 0 {
		t.Fatal("stopped a manually started unit")
	}
	// Auto-started: stopped after the idle timeout only.
	o.set("", false, false)
	g.lastHealthy = time.Time{}
	post(t, srv.URL+"/v1/chat/completions")
	c.add(29 * time.Minute)
	g.idleCheck()
	if o.stops.Load() != 0 {
		t.Fatal("stopped before the idle timeout")
	}
	c.add(2 * time.Minute)
	g.idleCheck()
	if o.stops.Load() != 1 || g.autoUnit != "" {
		t.Fatalf("stops=%d auto=%q", o.stops.Load(), g.autoUnit)
	}
}

func TestDesktopUseStopsAutoStarted(t *testing.T) {
	o := newFakeOwner(t)
	g, srv := newTestGate(t, o)
	post(t, srv.URL+"/v1/chat/completions")
	o.mu.Lock()
	o.busy = true
	o.mu.Unlock()
	g.mu.Lock()
	g.inflight = 1
	g.mu.Unlock()
	g.idleCheck()
	if o.stops.Load() != 0 {
		t.Fatal("stopped with a request in flight")
	}
	g.mu.Lock()
	g.inflight = 0
	g.mu.Unlock()
	g.idleCheck()
	if o.stops.Load() != 1 {
		t.Fatal("not stopped while the desktop is in use")
	}
}

func TestStreamingIsFlushed(t *testing.T) {
	o := newFakeOwner(t)
	o.set("strata-headless-iq3-s.service", true, false)
	_, srv := newTestGate(t, o)
	resp, err := http.Post(srv.URL+"/v1/stream", "application/json", strings.NewReader("{}"))
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	r := bufio.NewReader(resp.Body)
	got := make(chan string, 1)
	go func() { line, _ := r.ReadString('\n'); got <- line }()
	select {
	case line := <-got:
		if line != "data: 1\n" {
			t.Fatalf("line %q", line)
		}
	case <-time.After(2 * time.Second):
		t.Fatal("first event was not flushed")
	}
	close(o.sse)
}

func TestStateFileRestore(t *testing.T) {
	o := newFakeOwner(t)
	path := t.TempDir() + "/state.json"
	cfg := gateConfig{BackendURL: o.backend.URL, ControlURL: o.control.URL, StateFile: path, StartTimeoutSec: 2}
	g, _ := newGate(cfg)
	g.mu.Lock()
	g.setAutoLocked("strata-headless-iq3-s.service")
	g.mu.Unlock()
	g2, _ := newGate(cfg)
	if g2.autoUnit != "strata-headless-iq3-s.service" {
		t.Fatalf("restored %q", g2.autoUnit)
	}
}

func TestSessionBusy(t *testing.T) {
	cases := []struct {
		props string
		busy  bool
	}{
		{"Remote=no\nService=greetd\nDesktop=Hyprland\nType=wayland\nClass=user\nActive=yes\n", true},
		{"Remote=yes\nService=sshd\nDesktop=\nType=tty\nClass=user\nActive=yes\n", false},
		{"Remote=no\nDesktop=Strata\nType=wayland\nClass=user\nActive=yes\n", false},
		{"Remote=no\nService=systemd-user\nDesktop=\nType=unspecified\nClass=manager\nActive=yes\n", false},
		{"Remote=no\nDesktop=Hyprland\nType=wayland\nClass=user\nActive=no\n", false},
	}
	for _, c := range cases {
		if got := sessionBusy(parseProps(c.props)); got != c.busy {
			t.Errorf("%q: got %v", c.props, got)
		}
	}
	ids := sessionIDs("10 1001 hermes  -     46039 user    -    no -\n 3 1000 attodao seat0 2058  user    tty1 no -\n")
	if strings.Join(ids, ",") != "10,3" {
		t.Errorf("ids %v", ids)
	}
}

func TestControlAPI(t *testing.T) {
	health := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(503) }))
	defer health.Close()
	var mu sync.Mutex
	state := map[string]string{"a.service": "inactive", "b.service": "inactive"}
	busy := false
	var calls []string
	c := newControl(controlConfig{
		Units:     []unitConfig{{"A", "a.service"}, {"B", "b.service"}},
		HealthURL: health.URL, Systemctl: "systemctl", Loginctl: "loginctl",
	})
	c.run = func(name string, args ...string) (string, error) {
		mu.Lock()
		defer mu.Unlock()
		switch {
		case name == "systemctl" && args[0] == "show":
			return state[args[len(args)-1]] + "\n", nil
		case name == "systemctl":
			calls = append(calls, args[0]+" "+args[2])
			if args[0] == "start" {
				state[args[2]] = "activating"
			}
			return "", nil
		case args[0] == "list-sessions":
			return " 3 1000 attodao seat0 2058 user tty1 no -\n", nil
		case args[0] == "show-session":
			if busy {
				return "Class=user\nType=wayland\nActive=yes\nRemote=no\nDesktop=Hyprland\n", nil
			}
			return "Class=user\nType=tty\nActive=yes\nRemote=no\nDesktop=\n", nil
		}
		return "", errors.New("unexpected")
	}
	srv := httptest.NewServer(c.handler())
	defer srv.Close()
	do := func(method, path, body string) (int, map[string]any) {
		req, _ := http.NewRequest(method, srv.URL+path, strings.NewReader(body))
		resp, err := http.DefaultClient.Do(req)
		if err != nil {
			t.Fatal(err)
		}
		defer resp.Body.Close()
		var m map[string]any
		json.NewDecoder(resp.Body).Decode(&m)
		return resp.StatusCode, m
	}
	if code, m := do("GET", "/v1/status", ""); code != 200 || m["unit"] != nil || m["busy"] != false || m["state"] != "inactive" {
		t.Fatalf("status %d %v", code, m)
	}
	busy = true
	if code, _ := do("POST", "/v1/start", ""); code != 409 {
		t.Fatalf("busy start %d", code)
	}
	busy = false
	if code, _ := do("POST", "/v1/start", `{"model":"X"}`); code != 400 {
		t.Fatalf("unknown model %d", code)
	}
	if code, m := do("POST", "/v1/start", `{"model":"B"}`); code != 202 || m["unit"] != "b.service" {
		t.Fatalf("start %d %v", code, m)
	}
	if code, m := do("POST", "/v1/start", ""); code != 200 || m["unit"] != "b.service" {
		t.Fatalf("second start %d %v", code, m)
	}
	if code, _ := do("POST", "/v1/stop", `{"unit":"evil.service"}`); code != 400 {
		t.Fatalf("unknown unit stop %d", code)
	}
	if code, _ := do("POST", "/v1/stop", `{"unit":"b.service"}`); code != 202 {
		t.Fatalf("stop %d", code)
	}
	if strings.Join(calls, ";") != "start b.service;stop b.service" {
		t.Fatalf("calls %v", calls)
	}
}

func TestMagicPacket(t *testing.T) {
	p, err := magicPacket("a8:a1:59:d6:46:8e")
	if err != nil || len(p) != 102 || p[0] != 0xff || p[5] != 0xff || p[6] != 0xa8 || p[101] != 0x8e {
		t.Fatalf("%v %x", err, p)
	}
	if _, err := magicPacket("nope"); err == nil {
		t.Fatal("invalid MAC accepted")
	}
}
