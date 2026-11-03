package main

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
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
	offs    atomic.Int32
	// offReply is the /v1/poweroff answer: "" accepts, otherwise a 409 reason.
	offReply string
	offHuman bool
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
	cm.HandleFunc("POST /v1/poweroff", func(w http.ResponseWriter, r *http.Request) {
		o.mu.Lock()
		defer o.mu.Unlock()
		o.offs.Add(1)
		if o.offReply != "" {
			writeJSON(w, 409, map[string]any{"error": "busy", "reason": o.offReply, "human": o.offHuman})
			return
		}
		writeJSON(w, 202, map[string]any{"poweroff": true})
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

// settle waits until the gate has finished its in-flight bookkeeping; the
// client can see the response before the handler's deferred end() runs.
func settle(g *gate) {
	for i := 0; i < 1000; i++ {
		g.mu.Lock()
		n := g.inflight
		g.mu.Unlock()
		if n == 0 {
			return
		}
		time.Sleep(time.Millisecond)
	}
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
	settle(g)
	c.add(time.Hour)
	g.idleCheck()
	if o.stops.Load() != 0 {
		t.Fatal("stopped a manually started unit")
	}
	// Auto-started: stopped after the idle timeout only.
	o.set("", false, false)
	g.lastHealthy = time.Time{}
	post(t, srv.URL+"/v1/chat/completions")
	settle(g)
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
	settle(g)
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

func TestWakeAwakeOwnerWithoutStartingStrata(t *testing.T) {
	o := newFakeOwner(t)
	g, srv := newTestGate(t, o)
	c := &clock{t: time.Unix(1000, 0)}
	g.now = c.now
	var wol atomic.Int32
	g.sendWOL = func(string, string) error { wol.Add(1); return nil }
	last := g.lastActivity
	code, body := post(t, srv.URL+"/_strata-wake/wake")
	var reply struct {
		Awake     bool      `json:"awake"`
		HoldUntil time.Time `json:"holdUntil"`
	}
	if err := json.Unmarshal([]byte(body), &reply); err != nil {
		t.Fatal(err)
	}
	if code != 200 || !reply.Awake || !reply.HoldUntil.Equal(c.now().Add(g.idleTimeout)) || wol.Load() != 0 || o.starts.Load() != 0 {
		t.Fatalf("code=%d body=%s wol=%d starts=%d", code, body, wol.Load(), o.starts.Load())
	}
	if g.inflight != 0 || !g.lastActivity.Equal(last) {
		t.Fatal("wake changed Strata activity")
	}
	resp, err := http.Get(srv.URL + "/_strata-wake/status")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	var status map[string]any
	json.NewDecoder(resp.Body).Decode(&status)
	if status["holdUntil"] != reply.HoldUntil.Format(time.RFC3339) {
		t.Fatalf("status=%v", status)
	}
}

func TestWakeUnreachableOwner(t *testing.T) {
	o := newFakeOwner(t)
	g, srv := newTestGate(t, o)
	var polls, wol atomic.Int32
	handler := o.control.Config.Handler
	control := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/v1/status" && polls.Add(1) <= 3 {
			w.WriteHeader(503)
			return
		}
		handler.ServeHTTP(w, r)
	}))
	defer control.Close()
	g.cfg.ControlURL = control.URL
	g.cfg.WOL = &wolConfig{MAC: "a8:a1:59:d6:46:8e", Broadcast: "unused"}
	g.sendWOL = func(string, string) error { wol.Add(1); return nil }
	code, body := post(t, srv.URL+"/_strata-wake/wake")
	if code != 200 || wol.Load() == 0 || !g.wokeByGate || o.starts.Load() != 0 {
		t.Fatalf("code=%d body=%s wol=%d woke=%v", code, body, wol.Load(), g.wokeByGate)
	}
}

func TestWakeRequiresPost(t *testing.T) {
	o := newFakeOwner(t)
	g, srv := newTestGate(t, o)
	resp, err := http.Get(srv.URL + "/_strata-wake/wake")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != 405 || !g.holdUntil.IsZero() {
		t.Fatalf("code=%d hold=%v", resp.StatusCode, g.holdUntil)
	}
}

func TestWakeHoldWithoutUnit(t *testing.T) {
	o := newFakeOwner(t)
	g, _ := newTestGate(t, o)
	c := &clock{t: time.Unix(1000, 0)}
	g.now = c.now
	g.cfg.PowerOff = true
	g.wokeByGate = true
	g.holdUntil = c.now().Add(g.idleTimeout)
	g.idleCheck()
	if o.offs.Load() != 0 {
		t.Fatal("powered off during hold")
	}
	c.add(g.idleTimeout + time.Second)
	g.idleCheck()
	if o.offs.Load() != 1 {
		t.Fatal("did not power off after hold")
	}
}

func TestWakeHoldAfterIdleStop(t *testing.T) {
	o := newFakeOwner(t)
	g, c := wokenIdleGate(t, o, true)
	g.holdUntil = c.now().Add(g.idleTimeout)
	g.idleCheck()
	if o.stops.Load() != 1 || o.offs.Load() != 0 || !g.wokeByGate {
		t.Fatal("idle stop did not preserve wake hold")
	}
	c.add(g.idleTimeout + time.Second)
	g.idleCheck()
	if o.offs.Load() != 1 {
		t.Fatal("did not power off after idle stop and hold expiry")
	}
}

func TestWakeHoldStateRestore(t *testing.T) {
	o := newFakeOwner(t)
	cfg := gateConfig{BackendURL: o.backend.URL, ControlURL: o.control.URL, StateFile: t.TempDir() + "/state.json"}
	g, err := newGate(cfg)
	if err != nil {
		t.Fatal(err)
	}
	g.holdUntil = time.Unix(2000, 0)
	g.mu.Lock()
	g.saveStateLocked()
	g.mu.Unlock()
	g2, err := newGate(cfg)
	if err != nil {
		t.Fatal(err)
	}
	if !g2.holdUntil.Equal(g.holdUntil) {
		t.Fatalf("restored=%v want=%v", g2.holdUntil, g.holdUntil)
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

// wokenIdleGate returns a gate that woke the owner, started Strata and has
// been idle past the timeout.
func wokenIdleGate(t *testing.T, o *fakeOwner, powerOff bool) (*gate, *clock) {
	g, srv := newTestGate(t, o)
	g.cfg.PowerOff = powerOff
	c := &clock{t: time.Unix(1000, 0)}
	g.now = c.now
	post(t, srv.URL+"/v1/chat/completions")
	settle(g)
	g.mu.Lock()
	g.wokeByGate = true
	g.mu.Unlock()
	c.add(31 * time.Minute)
	return g, c
}

func TestPowerOffAfterIdleWhenWoken(t *testing.T) {
	o := newFakeOwner(t)
	g, _ := wokenIdleGate(t, o, true)
	g.idleCheck()
	if o.stops.Load() != 1 || o.offs.Load() != 1 || g.wokeByGate || g.powerOffPending {
		t.Fatalf("stops=%d offs=%d woke=%v pending=%v", o.stops.Load(), o.offs.Load(), g.wokeByGate, g.powerOffPending)
	}
}

func TestNoPowerOffWhenDisabledOrNotWoken(t *testing.T) {
	o := newFakeOwner(t)
	g, _ := wokenIdleGate(t, o, false)
	g.idleCheck()
	if o.stops.Load() != 1 || o.offs.Load() != 0 {
		t.Fatalf("disabled: stops=%d offs=%d", o.stops.Load(), o.offs.Load())
	}
	o2 := newFakeOwner(t)
	g2, _ := wokenIdleGate(t, o2, true)
	g2.wokeByGate = false
	g2.idleCheck()
	if o2.stops.Load() != 1 || o2.offs.Load() != 0 {
		t.Fatalf("not woken: stops=%d offs=%d", o2.stops.Load(), o2.offs.Load())
	}
}

func TestPowerOffRetriesWhileBusyAndGivesUpForPeople(t *testing.T) {
	o := newFakeOwner(t)
	o.offReply = "1 Docker container(s) running"
	g, _ := wokenIdleGate(t, o, true)
	g.idleCheck()
	if o.offs.Load() != 1 || !g.powerOffPending {
		t.Fatalf("offs=%d pending=%v", o.offs.Load(), g.powerOffPending)
	}
	g.idleCheck()
	if o.offs.Load() != 2 || !g.powerOffPending {
		t.Fatalf("retry: offs=%d pending=%v", o.offs.Load(), g.powerOffPending)
	}
	o.mu.Lock()
	o.offReply, o.offHuman = "session 3 of attodao (wayland)", true
	o.mu.Unlock()
	g.idleCheck()
	if g.powerOffPending || g.wokeByGate {
		t.Fatal("kept trying although a person logged in")
	}
	g.idleCheck()
	if o.offs.Load() != 3 {
		t.Fatalf("offs=%d", o.offs.Load())
	}
}

func TestDesktopUseCancelsPowerOff(t *testing.T) {
	o := newFakeOwner(t)
	g, c := wokenIdleGate(t, o, true)
	c.add(-30 * time.Minute) // not idle yet
	o.mu.Lock()
	o.busy = true
	o.mu.Unlock()
	g.idleCheck()
	if o.stops.Load() != 1 || o.offs.Load() != 0 || g.wokeByGate {
		t.Fatalf("stops=%d offs=%d woke=%v", o.stops.Load(), o.offs.Load(), g.wokeByGate)
	}
}

func TestNewRequestCancelsPendingPowerOff(t *testing.T) {
	o := newFakeOwner(t)
	o.offReply = "a heavy job is running"
	g, _ := wokenIdleGate(t, o, true)
	g.idleCheck()
	if !g.powerOffPending {
		t.Fatal("no pending power-off")
	}
	if e := g.bringUp(); e != nil {
		t.Fatal(e)
	}
	if g.powerOffPending || !g.wokeByGate || g.autoUnit == "" {
		t.Fatalf("pending=%v woke=%v auto=%q", g.powerOffPending, g.wokeByGate, g.autoUnit)
	}
}

func TestPowerOffBlocker(t *testing.T) {
	root := t.TempDir()
	lock := root + "/heavy.lock"
	os.WriteFile(lock, nil, 0o666)
	os.MkdirAll(root+"/system.slice", 0o755)
	sessions := ""
	unit := "inactive"
	c := newControl(controlConfig{Units: []unitConfig{{"A", "a.service"}}, Systemctl: "systemctl", Loginctl: "loginctl",
		HeavyLock: lock, CgroupRoot: root})
	c.run = func(name string, args ...string) (string, error) {
		switch {
		case name == "systemctl":
			return unit + "\n", nil
		case args[0] == "list-sessions":
			return sessions, nil
		default:
			if args[1] == "5" {
				return "Class=user\nName=hermes\nRemote=yes\nType=tty\n", nil
			}
			if args[1] == "3" {
				return "Class=user\nName=attodao\nRemote=no\nType=wayland\n", nil
			}
			return "Class=greeter\nName=greeter\nRemote=no\nType=wayland\n", nil
		}
	}
	check := func(want string, human bool) {
		t.Helper()
		got, h := c.powerOffBlocker()
		if !strings.Contains(got, want) || (want == "" && got != "") || h != human {
			t.Fatalf("got %q %v, want %q %v", got, h, want, human)
		}
	}
	check("", false)
	sessions = " 1 975 greeter seat0 1 greeter tty1 no -\n"
	check("", false) // the greeter alone is nobody
	unit = "active"
	check("a.service is active", false)
	unit = "inactive"
	sessions += " 5 1001 hermes - 6417 user - no -\n"
	check("session 5 of hermes", false) // SSH only postpones
	sessions += " 3 1000 attodao seat0 2063 user tty1 no -\n"
	check("session 3 of attodao", true)
	sessions = ""
	os.MkdirAll(root+"/system.slice/docker-abc.scope", 0o755)
	check("1 Docker container", false)
	os.Remove(root + "/system.slice/docker-abc.scope")
	f, _ := os.Open(lock)
	syscall.Flock(int(f.Fd()), syscall.LOCK_EX)
	check("heavy job", false)
	f.Close()
	check("", false)
}
