// strata-wake starts Strata on demand. `gate` runs next to the gateway's
// Traefik and proxies the API, waking the owner host (Wake-on-LAN) and
// starting Strata for POST requests, and stopping what it started after
// idleness. `control` runs on the owner and starts/stops the Strata units and
// reports whether its desktop is in use.
// POST /_strata-wake/wake wakes the owner without starting Strata and keeps it on for idleTimeoutSec after the last call.
package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"
)

const version = "0.2.0"

// ---------------------------------------------------------------- control

type unitConfig struct {
	Model string `json:"model"`
	Unit  string `json:"unit"`
}

type controlConfig struct {
	Listen string `json:"listen"`
	// HeavyLock and CgroupRoot are checked before powering off: a held heavy
	// lock or a running Docker container (CI job) postpones it.
	HeavyLock  string       `json:"heavyLock"`
	CgroupRoot string       `json:"cgroupRoot"`
	Units      []unitConfig `json:"units"`
	HealthURL  string       `json:"healthUrl"`
	Systemctl  string       `json:"systemctl"`
	Loginctl   string       `json:"loginctl"`
}

// controlStatus is the /v1/status body shared by control and gate.
type controlStatus struct {
	Unit       *string `json:"unit"`
	State      string  `json:"state"`
	Healthy    bool    `json:"healthy"`
	Busy       bool    `json:"busy"`
	BusyReason string  `json:"busyReason"`
}

type control struct {
	cfg    controlConfig
	run    func(name string, args ...string) (string, error)
	client *http.Client

	mu       sync.Mutex
	lastBusy *bool
}

func runCommand(name string, args ...string) (string, error) {
	out, err := exec.Command(name, args...).Output()
	return string(out), err
}

func newControl(cfg controlConfig) *control {
	return &control{cfg: cfg, run: runCommand, client: &http.Client{Timeout: 3 * time.Second}}
}

// parseProps parses `key=value` lines from `loginctl show-session -p ...`.
func parseProps(text string) map[string]string {
	m := map[string]string{}
	for _, line := range strings.Split(text, "\n") {
		if k, v, ok := strings.Cut(strings.TrimSpace(line), "="); ok {
			m[k] = v
		}
	}
	return m
}

// sessionBusy reports whether a logind session is a local, active graphical
// user session other than the Strata API-only session.
func sessionBusy(p map[string]string) bool {
	return p["Class"] == "user" &&
		(p["Type"] == "wayland" || p["Type"] == "x11") &&
		p["Active"] == "yes" &&
		p["Remote"] == "no" &&
		!strings.EqualFold(p["Desktop"], "strata")
}

// sessionIDs returns the first column of `loginctl list-sessions --no-legend`.
func sessionIDs(text string) []string {
	var ids []string
	for _, line := range strings.Split(text, "\n") {
		if f := strings.Fields(line); len(f) > 0 {
			ids = append(ids, f[0])
		}
	}
	return ids
}

func (c *control) busy() (bool, string) {
	out, err := c.run(c.cfg.Loginctl, "list-sessions", "--no-legend")
	if err != nil {
		log.Printf("loginctl list-sessions: %v", err)
		return false, ""
	}
	for _, id := range sessionIDs(out) {
		props, err := c.run(c.cfg.Loginctl, "show-session", id, "-p", "Class", "-p", "Type", "-p", "Active", "-p", "Remote", "-p", "Desktop")
		if err != nil {
			continue
		}
		p := parseProps(props)
		if sessionBusy(p) {
			return true, fmt.Sprintf("session %s (%s)", id, p["Desktop"])
		}
	}
	return false, ""
}

func (c *control) unitState(unit string) string {
	out, err := c.run(c.cfg.Systemctl, "show", "-p", "ActiveState", "--value", unit)
	if err != nil {
		return "unknown"
	}
	return strings.TrimSpace(out)
}

func (c *control) status() controlStatus {
	var s controlStatus
	for i, u := range c.cfg.Units {
		st := c.unitState(u.Unit)
		if i == 0 {
			s.State = st
		}
		if st == "active" || st == "activating" {
			name := u.Unit
			s.Unit, s.State = &name, st
			break
		}
	}
	if resp, err := c.client.Get(c.cfg.HealthURL); err == nil {
		io.Copy(io.Discard, resp.Body)
		resp.Body.Close()
		s.Healthy = resp.StatusCode == http.StatusOK
	}
	s.Busy, s.BusyReason = c.busy()
	c.mu.Lock()
	if c.lastBusy == nil || *c.lastBusy != s.Busy {
		if s.Busy {
			log.Printf("desktop in use: %s", s.BusyReason)
		} else {
			log.Printf("desktop not in use")
		}
		b := s.Busy
		c.lastBusy = &b
	}
	c.mu.Unlock()
	return s
}

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	json.NewEncoder(w).Encode(v)
}

func (c *control) knownUnit(unit string) bool {
	for _, u := range c.cfg.Units {
		if u.Unit == unit {
			return true
		}
	}
	return false
}

func (c *control) handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /v1/status", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, c.status())
	})
	mux.HandleFunc("POST /v1/start", func(w http.ResponseWriter, r *http.Request) {
		var body struct {
			Model string `json:"model"`
		}
		data, _ := io.ReadAll(io.LimitReader(r.Body, 1<<16))
		if len(bytes.TrimSpace(data)) > 0 && json.Unmarshal(data, &body) != nil {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid JSON"})
			return
		}
		if len(c.cfg.Units) == 0 {
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "no units configured"})
			return
		}
		unit := c.cfg.Units[0].Unit
		if body.Model != "" {
			unit = ""
			for _, u := range c.cfg.Units {
				if u.Model == body.Model {
					unit = u.Unit
				}
			}
			if unit == "" {
				writeJSON(w, http.StatusBadRequest, map[string]string{"error": "unknown model " + body.Model})
				return
			}
		}
		s := c.status()
		if s.Unit != nil {
			writeJSON(w, http.StatusOK, map[string]any{"started": false, "unit": *s.Unit})
			return
		}
		if s.Busy {
			writeJSON(w, http.StatusConflict, map[string]any{"error": "busy", "busyReason": s.BusyReason})
			return
		}
		if _, err := c.run(c.cfg.Systemctl, "start", "--no-block", unit); err != nil {
			log.Printf("start %s: %v", unit, err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "systemctl start failed"})
			return
		}
		log.Printf("started %s", unit)
		writeJSON(w, http.StatusAccepted, map[string]any{"started": true, "unit": unit})
	})
	mux.HandleFunc("POST /v1/stop", func(w http.ResponseWriter, r *http.Request) {
		var body struct {
			Unit string `json:"unit"`
		}
		if err := json.NewDecoder(io.LimitReader(r.Body, 1<<16)).Decode(&body); err != nil || !c.knownUnit(body.Unit) {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "unknown unit"})
			return
		}
		if _, err := c.run(c.cfg.Systemctl, "stop", "--no-block", body.Unit); err != nil {
			log.Printf("stop %s: %v", body.Unit, err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "systemctl stop failed"})
			return
		}
		log.Printf("stopped %s", body.Unit)
		writeJSON(w, http.StatusAccepted, map[string]any{"stopped": true, "unit": body.Unit})
	})
	mux.HandleFunc("POST /v1/poweroff", func(w http.ResponseWriter, r *http.Request) {
		reason, human := c.powerOffBlocker()
		if reason != "" {
			writeJSON(w, http.StatusConflict, map[string]any{"error": "busy", "reason": reason, "human": human})
			return
		}
		log.Printf("powering off on request of the gateway")
		writeJSON(w, http.StatusAccepted, map[string]any{"poweroff": true})
		go func() {
			time.Sleep(time.Second)
			if _, err := c.run(c.cfg.Systemctl, "poweroff", "--no-block"); err != nil {
				log.Printf("poweroff: %v", err)
			}
		}()
	})
	return mux
}

// powerOffBlocker returns why the owner must stay on ("" when it may power
// off) and whether the reason is a person at the machine (a local session).
func (c *control) powerOffBlocker() (string, bool) {
	for _, u := range c.cfg.Units {
		if st := c.unitState(u.Unit); st == "active" || st == "activating" {
			return u.Unit + " is " + st, false
		}
	}
	out, err := c.run(c.cfg.Loginctl, "list-sessions", "--no-legend")
	if err != nil {
		return "cannot list sessions", false
	}
	remote := ""
	for _, id := range sessionIDs(out) {
		props, err := c.run(c.cfg.Loginctl, "show-session", id, "-p", "Class", "-p", "Name", "-p", "Remote", "-p", "Type")
		if err != nil {
			continue
		}
		p := parseProps(props)
		if p["Class"] != "user" {
			continue
		}
		reason := fmt.Sprintf("session %s of %s (%s)", id, p["Name"], p["Type"])
		// A local login means a person took the machine over; a remote
		// (SSH) session only postpones the power-off.
		if p["Remote"] != "yes" {
			return reason, true
		}
		if remote == "" {
			remote = reason
		}
	}
	if remote != "" {
		return remote, false
	}
	if c.cfg.CgroupRoot != "" {
		if m, _ := filepath.Glob(filepath.Join(c.cfg.CgroupRoot, "system.slice", "docker-*.scope")); len(m) > 0 {
			return fmt.Sprintf("%d Docker container(s) running", len(m)), false
		}
	}
	if c.cfg.HeavyLock != "" {
		if f, err := os.Open(c.cfg.HeavyLock); err == nil {
			defer f.Close()
			if syscall.Flock(int(f.Fd()), syscall.LOCK_SH|syscall.LOCK_NB) != nil {
				return "a heavy job is running", false
			}
			syscall.Flock(int(f.Fd()), syscall.LOCK_UN)
		}
	}
	return "", false
}

// ---------------------------------------------------------------- gate

type wolConfig struct {
	MAC       string `json:"mac"`
	Broadcast string `json:"broadcast"`
}

type gateConfig struct {
	Listen          string     `json:"listen"`
	BackendURL      string     `json:"backendUrl"`
	HealthPath      string     `json:"healthPath"`
	ControlURL      string     `json:"controlUrl"`
	WOL             *wolConfig `json:"wol"`
	IdleTimeoutSec  int        `json:"idleTimeoutSec"`
	WakeTimeoutSec  int        `json:"wakeTimeoutSec"`
	StartTimeoutSec int        `json:"startTimeoutSec"`
	StateFile       string     `json:"stateFile"`
	// PowerOff powers the owner off after an idle stop when the gate woke it.
	PowerOff bool `json:"powerOff"`
}

// apiError is returned to API clients in the OpenAI error shape.
type apiError struct {
	code       int
	message    string
	retryAfter int
}

func (e *apiError) Error() string { return e.message }

func unavailable(msg string) *apiError {
	return &apiError{code: http.StatusServiceUnavailable, message: msg}
}

var errBusy = &apiError{code: http.StatusServiceUnavailable, message: "attodesk desktop is in use; Strata was not started", retryAfter: 600}

func writeAPIError(w http.ResponseWriter, e *apiError) {
	if e.retryAfter > 0 {
		w.Header().Set("Retry-After", fmt.Sprint(e.retryAfter))
	}
	writeJSON(w, e.code, map[string]any{"error": map[string]string{"message": e.message, "type": "strata_unavailable"}})
}

type startCall struct {
	done chan struct{}
	err  *apiError
}

type gate struct {
	cfg     gateConfig
	backend *url.URL
	proxy   *httputil.ReverseProxy
	client  *http.Client
	now     func() time.Time
	sendWOL func(mac, broadcast string) error

	pollEvery, wolEvery, healthTTL, idleCheckEvery time.Duration
	wakeTimeout, startTimeout, idleTimeout         time.Duration

	mu           sync.Mutex
	state        string
	autoUnit     string
	inflight     int
	lastActivity time.Time
	lastHealthy  time.Time
	lastError    string
	pending      *startCall
	pendingWake  *startCall
	holdUntil    time.Time
	// wokeByGate: the owner was off and the gate woke it; powerOffPending: an
	// idle stop happened on such an owner and the power-off is still to be done.
	wokeByGate      bool
	powerOffPending bool
}

func newGate(cfg gateConfig) (*gate, error) {
	backend, err := url.Parse(cfg.BackendURL)
	if err != nil || backend.Host == "" {
		return nil, fmt.Errorf("invalid backendUrl %q", cfg.BackendURL)
	}
	if cfg.HealthPath == "" {
		cfg.HealthPath = "/health"
	}
	g := &gate{
		cfg:            cfg,
		backend:        backend,
		client:         &http.Client{Timeout: 3 * time.Second},
		now:            time.Now,
		sendWOL:        sendMagicPacket,
		pollEvery:      5 * time.Second,
		wolEvery:       60 * time.Second,
		healthTTL:      5 * time.Second,
		idleCheckEvery: 60 * time.Second,
		wakeTimeout:    time.Duration(cfg.WakeTimeoutSec) * time.Second,
		startTimeout:   time.Duration(cfg.StartTimeoutSec) * time.Second,
		idleTimeout:    time.Duration(cfg.IdleTimeoutSec) * time.Second,
		state:          "unknown",
	}
	g.proxy = &httputil.ReverseProxy{
		Rewrite: func(r *httputil.ProxyRequest) {
			r.SetURL(backend)
			r.SetXForwarded()
		},
		FlushInterval: -1,
		ErrorHandler: func(w http.ResponseWriter, r *http.Request, err error) {
			g.mu.Lock()
			g.lastHealthy = time.Time{}
			g.mu.Unlock()
			log.Printf("proxy %s %s: %v", r.Method, r.URL.Path, err)
			writeAPIError(w, &apiError{code: http.StatusBadGateway, message: "Strata backend error"})
		},
	}
	g.lastActivity = g.now()
	g.loadState()
	return g, nil
}

func (g *gate) setState(s string) {
	g.mu.Lock()
	defer g.mu.Unlock()
	if g.state != s {
		log.Printf("state %s -> %s", g.state, s)
		g.state = s
	}
}

func (g *gate) loadState() {
	if g.cfg.StateFile == "" {
		return
	}
	data, err := os.ReadFile(g.cfg.StateFile)
	if err != nil {
		return
	}
	var st gateState
	if json.Unmarshal(data, &st) == nil {
		g.autoUnit, g.wokeByGate, g.powerOffPending = st.AutoStartedUnit, st.WokeByGate, st.PowerOffPending
		g.holdUntil = st.HoldUntil
		if st.AutoStartedUnit != "" || st.WokeByGate || !st.HoldUntil.IsZero() {
			log.Printf("restored state: auto-started unit %q, woken by gate %v, power-off pending %v",
				st.AutoStartedUnit, st.WokeByGate, st.PowerOffPending)
		}
	}
}

type gateState struct {
	HoldUntil       time.Time `json:"holdUntil"`
	AutoStartedUnit string    `json:"autoStartedUnit"`
	WokeByGate      bool      `json:"wokeByGate"`
	PowerOffPending bool      `json:"powerOffPending"`
}

// setAutoLocked records (or clears with "") the unit the gate started. Call with mu held.
func (g *gate) setAutoLocked(unit string) {
	g.autoUnit = unit
	g.saveStateLocked()
}

// saveStateLocked persists the gate's ownership state. Call with mu held.
func (g *gate) saveStateLocked() {
	if g.cfg.StateFile == "" {
		return
	}
	data, _ := json.Marshal(gateState{HoldUntil: g.holdUntil, AutoStartedUnit: g.autoUnit, WokeByGate: g.wokeByGate, PowerOffPending: g.powerOffPending})
	tmp := g.cfg.StateFile + ".tmp"
	if err := os.WriteFile(tmp, data, 0o600); err == nil {
		err = os.Rename(tmp, g.cfg.StateFile)
		if err != nil {
			log.Printf("state file: %v", err)
		}
	} else {
		log.Printf("state file: %v", err)
	}
}

func (g *gate) checkHealth(ctx context.Context) bool {
	req, _ := http.NewRequestWithContext(ctx, http.MethodGet, g.cfg.BackendURL+g.cfg.HealthPath, nil)
	resp, err := g.client.Do(req)
	if err != nil {
		return false
	}
	io.Copy(io.Discard, resp.Body)
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return false
	}
	g.mu.Lock()
	g.lastHealthy = g.now()
	g.mu.Unlock()
	return true
}

func (g *gate) controlStatus() (controlStatus, error) {
	var s controlStatus
	resp, err := g.client.Get(g.cfg.ControlURL + "/v1/status")
	if err != nil {
		return s, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return s, fmt.Errorf("control status %d", resp.StatusCode)
	}
	return s, json.NewDecoder(resp.Body).Decode(&s)
}

func (g *gate) controlPost(path string, body any) (int, map[string]any, error) {
	data, _ := json.Marshal(body)
	resp, err := g.client.Post(g.cfg.ControlURL+path, "application/json", bytes.NewReader(data))
	if err != nil {
		return 0, nil, err
	}
	defer resp.Body.Close()
	var out map[string]any
	json.NewDecoder(resp.Body).Decode(&out)
	return resp.StatusCode, out, nil
}

func (g *gate) fail(e *apiError) *apiError {
	g.mu.Lock()
	g.lastError = e.message
	g.mu.Unlock()
	g.setState("stopped")
	log.Printf("start failed: %s", e.message)
	return e
}

func (g *gate) wakeOwner() *apiError {
	if _, err := g.controlStatus(); err == nil {
		return nil
	}
	if g.cfg.WOL == nil {
		return unavailable("attodesk control API is unreachable and Wake-on-LAN is not configured")
	}
	deadline := g.now().Add(g.wakeTimeout)
	var lastWOL time.Time
	for {
		if g.now().Sub(lastWOL) >= g.wolEvery {
			if err := g.sendWOL(g.cfg.WOL.MAC, g.cfg.WOL.Broadcast); err != nil {
				log.Printf("wake-on-lan: %v", err)
			} else {
				log.Printf("sent wake-on-lan to %s", g.cfg.WOL.MAC)
			}
			lastWOL = g.now()
		}
		if !g.now().Before(deadline) {
			return unavailable("attodesk did not wake up")
		}
		time.Sleep(g.pollEvery)
		if _, err := g.controlStatus(); err == nil {
			g.mu.Lock()
			g.wokeByGate = true
			g.saveStateLocked()
			g.mu.Unlock()
			log.Printf("owner woke up")
			return nil
		}
	}
}

// bringUp wakes the owner if needed, starts Strata and waits until healthy.
func (g *gate) bringUp() *apiError {
	g.mu.Lock()
	if g.powerOffPending {
		g.powerOffPending = false
		g.saveStateLocked()
	}
	g.mu.Unlock()
	st, err := g.controlStatus()
	if err != nil {
		g.setState("waking")
		if e := g.wakeOwner(); e != nil {
			return g.fail(e)
		}
		st, err = g.controlStatus()
		if err != nil {
			return g.fail(unavailable("attodesk control API is unreachable"))
		}
	}
	if st.Healthy && g.checkHealth(context.Background()) {
		g.setState("ready")
		return nil
	}
	if st.Unit == nil {
		if st.Busy {
			return g.fail(errBusy)
		}
		code, out, err := g.controlPost("/v1/start", map[string]string{})
		switch {
		case err != nil:
			return g.fail(unavailable("attodesk control API is unreachable"))
		case code == http.StatusAccepted:
			unit, _ := out["unit"].(string)
			g.mu.Lock()
			g.setAutoLocked(unit)
			g.mu.Unlock()
			log.Printf("started %s on demand", unit)
		case code == http.StatusOK:
			// Someone else started it; not ours to stop.
		case code == http.StatusConflict:
			return g.fail(errBusy)
		default:
			return g.fail(unavailable(fmt.Sprintf("attodesk control API returned %d", code)))
		}
	}
	g.setState("starting")
	deadline := g.now().Add(g.startTimeout)
	for !g.checkHealth(context.Background()) {
		if !g.now().Before(deadline) {
			e := g.fail(&apiError{code: http.StatusGatewayTimeout, message: "Strata did not become healthy in time"})
			return e
		}
		time.Sleep(g.pollEvery)
	}
	g.setState("ready")
	return nil
}

// ensureUp shares one bring-up among concurrent requests. A cancelled client
// stops waiting but the bring-up continues.
func (g *gate) ensureUp(ctx context.Context) *apiError {
	g.mu.Lock()
	if g.pending == nil {
		c := &startCall{done: make(chan struct{})}
		g.pending = c
		go func() {
			c.err = g.bringUp()
			g.mu.Lock()
			g.pending = nil
			g.mu.Unlock()
			close(c.done)
		}()
	}
	c := g.pending
	g.mu.Unlock()
	select {
	case <-c.done:
		return c.err
	case <-ctx.Done():
		return &apiError{code: 499, message: "client went away"}
	}
}

// ensureAwake shares one wake-up among concurrent requests. A cancelled client
// stops waiting but the wake-up continues.
func (g *gate) ensureAwake(ctx context.Context) *apiError {
	g.mu.Lock()
	if g.pendingWake == nil {
		c := &startCall{done: make(chan struct{})}
		g.pendingWake = c
		go func() {
			c.err = g.wakeOwner()
			g.mu.Lock()
			g.pendingWake = nil
			g.mu.Unlock()
			close(c.done)
		}()
	}
	c := g.pendingWake
	g.mu.Unlock()
	select {
	case <-c.done:
		return c.err
	case <-ctx.Done():
		return &apiError{code: 499, message: "client went away"}
	}
}

func (g *gate) begin() {
	g.mu.Lock()
	g.inflight++
	g.lastActivity = g.now()
	g.mu.Unlock()
}

func (g *gate) end() {
	g.mu.Lock()
	g.inflight--
	g.lastActivity = g.now()
	g.mu.Unlock()
}

func (g *gate) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path == "/_strata-wake/status" {
		g.mu.Lock()
		body := map[string]any{
			"state": g.state, "autoStartedUnit": g.autoUnit, "inflight": g.inflight,
			"lastActivity": g.lastActivity.Format(time.RFC3339), "lastError": g.lastError,
			"holdUntil":  g.holdUntil.Format(time.RFC3339),
			"wokeByGate": g.wokeByGate, "powerOffPending": g.powerOffPending,
		}
		g.mu.Unlock()
		writeJSON(w, http.StatusOK, body)
		return
	}
	if r.URL.Path == "/_strata-wake/wake" {
		if r.Method != http.MethodPost {
			writeJSON(w, 405, map[string]string{"error": "use POST"})
			return
		}
		g.mu.Lock()
		g.holdUntil = g.now().Add(g.idleTimeout)
		g.powerOffPending = false
		g.saveStateLocked()
		g.mu.Unlock()
		if e := g.ensureAwake(r.Context()); e != nil {
			if e.code != 499 {
				writeAPIError(w, e)
			}
			return
		}
		g.mu.Lock()
		hold := g.holdUntil.Format(time.RFC3339)
		g.mu.Unlock()
		writeJSON(w, 200, map[string]any{"awake": true, "holdUntil": hold})
		return
	}
	g.begin()
	defer g.end()
	g.mu.Lock()
	fresh := !g.lastHealthy.IsZero() && g.now().Sub(g.lastHealthy) < g.healthTTL
	g.mu.Unlock()
	if !fresh && !g.checkHealth(r.Context()) {
		if r.Method != http.MethodPost {
			writeAPIError(w, unavailable("Strata is not running; send a POST to start it"))
			return
		}
		if e := g.ensureUp(r.Context()); e != nil {
			if e.code != 499 {
				writeAPIError(w, e)
			}
			return
		}
	}
	g.proxy.ServeHTTP(w, r)
}

// idleCheck stops the unit the gate started when it has been idle long enough
// or the owner's desktop came into use, forgets units that went away, and
// powers off an owner the gate woke once it is idle again.
func (g *gate) idleCheck() {
	g.mu.Lock()
	unit, inflight, last, pendingOff := g.autoUnit, g.inflight, g.lastActivity, g.powerOffPending
	woke, hold := g.wokeByGate, g.holdUntil
	g.mu.Unlock()
	held := g.now().Before(hold)
	if unit == "" && !pendingOff {
		if !(woke && g.cfg.PowerOff) || held {
			return
		}
		g.mu.Lock()
		g.powerOffPending = true
		g.saveStateLocked()
		g.mu.Unlock()
		pendingOff = true
		log.Printf("wake hold expired; powering off the owner the gate woke")
	}
	st, err := g.controlStatus()
	if err != nil {
		if pendingOff {
			// Unreachable: already off (or gone); nothing left to do.
			g.mu.Lock()
			g.wokeByGate, g.powerOffPending = false, false
			g.saveStateLocked()
			g.mu.Unlock()
		}
		return
	}
	if inflight > 0 {
		return
	}
	if unit == "" {
		g.tryPowerOff()
		return
	}
	if st.Unit == nil || *st.Unit != unit {
		g.mu.Lock()
		g.setAutoLocked("")
		g.mu.Unlock()
		log.Printf("%s is no longer running; forgetting it", unit)
		return
	}
	reason := ""
	if g.now().Sub(last) >= g.idleTimeout {
		reason = "idle"
	} else if st.Busy {
		reason = "desktop in use"
	}
	if reason == "" {
		return
	}
	code, _, err := g.controlPost("/v1/stop", map[string]string{"unit": unit})
	if err != nil || code != http.StatusAccepted {
		log.Printf("stop %s (%s) failed: %v %d", unit, reason, err, code)
		return
	}
	g.mu.Lock()
	g.autoUnit = ""
	g.lastHealthy = time.Time{}
	switch {
	case !g.wokeByGate || !g.cfg.PowerOff:
	case reason == "idle":
		g.powerOffPending = !g.now().Before(g.holdUntil)
	default:
		// Someone uses the desktop: the machine is theirs now.
		g.wokeByGate = false
	}
	g.saveStateLocked()
	pendingOff = g.powerOffPending
	g.mu.Unlock()
	g.setState("stopped")
	log.Printf("stopped %s (%s)", unit, reason)
	if pendingOff {
		g.tryPowerOff()
	}
}

// tryPowerOff asks the owner to power off. The owner refuses while anyone is
// logged in (then the gate gives up: a person took over) or while other work
// runs (then the gate retries on the next check).
func (g *gate) tryPowerOff() {
	code, out, err := g.controlPost("/v1/poweroff", map[string]string{})
	g.mu.Lock()
	defer g.mu.Unlock()
	switch {
	case err != nil:
		return
	case code == http.StatusAccepted:
		log.Printf("powering off the owner (woken by the gate, idle)")
		g.wokeByGate, g.powerOffPending = false, false
		g.saveStateLocked()
	case code == http.StatusConflict:
		reason, _ := out["reason"].(string)
		if human, _ := out["human"].(bool); human {
			log.Printf("not powering off: %s; leaving the owner on", reason)
			g.wokeByGate, g.powerOffPending = false, false
			g.saveStateLocked()
		} else if g.lastError != "poweroff: "+reason {
			log.Printf("power-off postponed: %s", reason)
			g.lastError = "poweroff: " + reason
		}
	default:
		log.Printf("power-off request failed: %d", code)
	}
}

func (g *gate) idleLoop(ctx context.Context) {
	t := time.NewTicker(g.idleCheckEvery)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			g.idleCheck()
		}
	}
}

// ---------------------------------------------------------------- wake-on-lan

func magicPacket(mac string) ([]byte, error) {
	hw, err := net.ParseMAC(mac)
	if err != nil || len(hw) != 6 {
		return nil, fmt.Errorf("invalid MAC %q", mac)
	}
	p := bytes.Repeat([]byte{0xff}, 6)
	for i := 0; i < 16; i++ {
		p = append(p, hw...)
	}
	return p, nil
}

// sendMagicPacket sends three magic packets one second apart.
func sendMagicPacket(mac, broadcast string) error {
	p, err := magicPacket(mac)
	if err != nil {
		return err
	}
	addr, err := net.ResolveUDPAddr("udp4", broadcast)
	if err != nil {
		return err
	}
	lc := net.ListenConfig{Control: func(_, _ string, c syscall.RawConn) error {
		var serr error
		if err := c.Control(func(fd uintptr) {
			serr = syscall.SetsockoptInt(int(fd), syscall.SOL_SOCKET, syscall.SO_BROADCAST, 1)
		}); err != nil {
			return err
		}
		return serr
	}}
	pc, err := lc.ListenPacket(context.Background(), "udp4", ":0")
	if err != nil {
		return err
	}
	defer pc.Close()
	for i := 0; i < 3; i++ {
		if i > 0 {
			time.Sleep(time.Second)
		}
		if _, err := pc.WriteTo(p, addr); err != nil {
			return err
		}
	}
	return nil
}

// ---------------------------------------------------------------- main

func readConfig(path string, v any) error {
	data, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	return json.Unmarshal(data, v)
}

func flagValue(args []string, name string) string {
	for i := 0; i+1 < len(args); i++ {
		if args[i] == name {
			return args[i+1]
		}
	}
	return ""
}

const usage = `strata-wake: start Strata on demand

usage:
  strata-wake gate    --config FILE    proxy on the gateway: wake the owner and start Strata for POSTs
  strata-wake control --config FILE    API on the owner: status/start/stop of the Strata units
  strata-wake status  --control-url URL
  strata-wake wol     --mac MAC --broadcast ADDR:PORT
  strata-wake --version

  gate: POST /_strata-wake/wake wakes the owner without starting Strata and keeps it on for idleTimeoutSec after the last call
`

func main() {
	log.SetFlags(0)
	if len(os.Args) < 2 {
		fmt.Fprint(os.Stderr, usage)
		os.Exit(2)
	}
	args := os.Args[2:]
	switch os.Args[1] {
	case "gate":
		var cfg gateConfig
		if err := readConfig(flagValue(args, "--config"), &cfg); err != nil {
			log.Fatalf("config: %v", err)
		}
		g, err := newGate(cfg)
		if err != nil {
			log.Fatal(err)
		}
		go g.idleLoop(context.Background())
		log.Printf("gate on %s -> %s (control %s, idle %ds)", cfg.Listen, cfg.BackendURL, cfg.ControlURL, cfg.IdleTimeoutSec)
		srv := &http.Server{Addr: cfg.Listen, Handler: g, ReadHeaderTimeout: 30 * time.Second}
		log.Fatal(srv.ListenAndServe())
	case "control":
		var cfg controlConfig
		if err := readConfig(flagValue(args, "--config"), &cfg); err != nil {
			log.Fatalf("config: %v", err)
		}
		c := newControl(cfg)
		var units []string
		for _, u := range cfg.Units {
			units = append(units, u.Unit)
		}
		log.Printf("control on %s for %s", cfg.Listen, strings.Join(units, ", "))
		srv := &http.Server{Addr: cfg.Listen, Handler: c.handler(), ReadHeaderTimeout: 10 * time.Second}
		log.Fatal(srv.ListenAndServe())
	case "status":
		u := flagValue(args, "--control-url")
		if u == "" {
			log.Fatal("--control-url is required")
		}
		resp, err := (&http.Client{Timeout: 5 * time.Second}).Get(strings.TrimSuffix(u, "/") + "/v1/status")
		if err != nil {
			log.Fatalf("control unreachable: %v", err)
		}
		defer resp.Body.Close()
		var v any
		if err := json.NewDecoder(resp.Body).Decode(&v); err != nil {
			log.Fatalf("status %d: %v", resp.StatusCode, err)
		}
		out, _ := json.MarshalIndent(v, "", "  ")
		fmt.Println(string(out))
	case "wol":
		mac, bc := flagValue(args, "--mac"), flagValue(args, "--broadcast")
		if mac == "" || bc == "" {
			log.Fatal("--mac and --broadcast are required")
		}
		if err := sendMagicPacket(mac, bc); err != nil {
			log.Fatal(err)
		}
		fmt.Printf("sent 3 magic packets for %s to %s\n", mac, bc)
	case "--version", "version":
		fmt.Println("strata-wake " + version)
	default:
		fmt.Fprint(os.Stderr, usage)
		os.Exit(2)
	}
}
