package main

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net"
	"os"
	"os/signal"
	"os/user"
	"path/filepath"
	"strconv"
	"sync"
	"syscall"
	"time"
)

type request struct {
	Op  string   `json:"op"` // stop, pause, resume, leave
	IDs []string `json:"ids,omitempty"`
	All bool     `json:"all,omitempty"`
}

type result struct {
	ID      string `json:"id"`
	Message string `json:"message,omitempty"`
	Error   string `json:"error,omitempty"`
}

type response struct {
	OK      bool     `json:"ok"`
	Message string   `json:"message,omitempty"`
	Error   string   `json:"error,omitempty"`
	Results []result `json:"results,omitempty"`
}

// send delivers one request to the agent and waits for its answer.
func send(c config, req request) (response, error) {
	var resp response
	conn, err := net.DialTimeout("unix", c.Socket, 5*time.Second)
	if err != nil {
		if errors.Is(err, syscall.EACCES) {
			return resp, fmt.Errorf("permission denied on %s: the user must be in group %q (log in again after adding it)", c.Socket, c.SocketGroup)
		}
		return resp, fmt.Errorf("cannot reach the agent at %s: %w", c.Socket, err)
	}
	defer conn.Close()
	// Stopping units and containers can take a while; the agent bounds each step.
	conn.SetDeadline(time.Now().Add(5 * time.Minute))
	if err := json.NewEncoder(conn).Encode(req); err != nil {
		return resp, err
	}
	if err := json.NewDecoder(bufio.NewReader(conn)).Decode(&resp); err != nil {
		return resp, fmt.Errorf("reading the agent's answer: %w", err)
	}
	return resp, nil
}

type agent struct {
	c     config
	mu    sync.Mutex // serializes collection and status writes
	reqMu sync.Mutex // serializes requests; held while stopping, without blocking refreshes
}

func writeStatus(c config, doc statusDoc) error {
	data, err := json.Marshal(doc)
	if err != nil {
		return err
	}
	tmp := c.StatusFile + ".tmp"
	if err := os.WriteFile(tmp, append(data, '\n'), 0o644); err != nil {
		return err
	}
	if err := os.Chmod(tmp, 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, c.StatusFile)
}

func (a *agent) refresh() statusDoc {
	doc := collect(a.c)
	if err := writeStatus(a.c, doc); err != nil {
		log.Printf("writing %s: %v", a.c.StatusFile, err)
	}
	return doc
}

func runAgent(c config) int {
	log.SetFlags(0)
	if err := os.MkdirAll(filepath.Dir(c.StatusFile), 0o755); err != nil {
		log.Printf("%v", err)
		return exitFailed
	}
	ln, err := listen(c)
	if err != nil {
		log.Printf("%v", err)
		return exitFailed
	}
	a := &agent{c: c}
	a.mu.Lock()
	a.refresh()
	a.mu.Unlock()

	go func() {
		interval := time.Duration(max(c.IntervalSec, 1)) * time.Second
		for range time.Tick(interval) {
			a.mu.Lock()
			a.refresh()
			a.mu.Unlock()
		}
	}()
	go func() {
		for {
			conn, err := ln.Accept()
			if err != nil {
				if errors.Is(err, net.ErrClosed) {
					return
				}
				log.Printf("accept: %v", err)
				time.Sleep(time.Second)
				continue
			}
			go a.serve(conn.(*net.UnixConn))
		}
	}()
	sigs := make(chan os.Signal, 1)
	signal.Notify(sigs, syscall.SIGTERM, syscall.SIGINT)
	<-sigs
	ln.Close()
	os.Remove(c.StatusFile)
	return 0
}

func listen(c config) (*net.UnixListener, error) {
	if err := os.MkdirAll(filepath.Dir(c.Socket), 0o755); err != nil {
		return nil, err
	}
	os.Remove(c.Socket)
	ln, err := net.ListenUnix("unix", &net.UnixAddr{Name: c.Socket, Net: "unix"})
	if err != nil {
		return nil, err
	}
	if c.SocketGroup != "" {
		g, err := user.LookupGroup(c.SocketGroup)
		if err != nil {
			ln.Close()
			return nil, fmt.Errorf("socket group %q: %w", c.SocketGroup, err)
		}
		gid, _ := strconv.Atoi(g.Gid)
		if err := os.Chown(c.Socket, 0, gid); err != nil {
			ln.Close()
			return nil, err
		}
	}
	if err := os.Chmod(c.Socket, 0o660); err != nil {
		ln.Close()
		return nil, err
	}
	return ln, nil
}

func peerName(conn *net.UnixConn) string {
	raw, err := conn.SyscallConn()
	if err != nil {
		return "?"
	}
	var cred *syscall.Ucred
	raw.Control(func(fd uintptr) {
		cred, _ = syscall.GetsockoptUcred(int(fd), syscall.SOL_SOCKET, syscall.SO_PEERCRED)
	})
	if cred == nil {
		return "?"
	}
	if u, err := user.LookupId(strconv.Itoa(int(cred.Uid))); err == nil {
		return u.Username
	}
	return "uid " + strconv.Itoa(int(cred.Uid))
}

func (a *agent) serve(conn *net.UnixConn) {
	defer conn.Close()
	conn.SetReadDeadline(time.Now().Add(10 * time.Second))
	var req request
	if err := json.NewDecoder(bufio.NewReader(&limitedReader{conn, 64 << 10})).Decode(&req); err != nil {
		json.NewEncoder(conn).Encode(response{Error: "bad request: " + err.Error()})
		return
	}
	conn.SetReadDeadline(time.Time{})
	who := peerName(conn)
	log.Printf("%s: %s %v all=%v", who, req.Op, req.IDs, req.All)
	a.reqMu.Lock()
	resp := a.handle(who, req)
	a.reqMu.Unlock()
	a.mu.Lock()
	a.refresh()
	a.mu.Unlock()
	if !resp.OK {
		log.Printf("%s: %s failed: %s", who, req.Op, resp.Error)
	}
	json.NewEncoder(conn).Encode(resp)
}

type limitedReader struct {
	r interface{ Read([]byte) (int, error) }
	n int
}

func (l *limitedReader) Read(p []byte) (int, error) {
	if l.n <= 0 {
		return 0, errors.New("request too large")
	}
	if len(p) > l.n {
		p = p[:l.n]
	}
	n, err := l.r.Read(p)
	l.n -= n
	return n, err
}

func (a *agent) handle(who string, req request) response {
	switch req.Op {
	case "stop":
		return a.stop(req)
	case "pause":
		return a.pause(who)
	case "resume":
		return a.resume()
	case "leave":
		return a.leave()
	default:
		return response{Error: fmt.Sprintf("unknown op %q", req.Op)}
	}
}

func (a *agent) stop(req request) response {
	doc := collect(a.c)
	byID := map[string]item{}
	for _, it := range doc.Items {
		byID[it.ID] = it
	}
	var targets []item
	var results []result
	if req.All {
		targets = doc.Items
		if len(targets) == 0 {
			return response{OK: true, Message: "nothing to stop"}
		}
	} else {
		for _, id := range req.IDs {
			if it, ok := byID[id]; ok {
				targets = append(targets, it)
			} else {
				results = append(results, result{ID: id, Error: "not found (already finished?)"})
			}
		}
	}
	out := make([]result, len(targets))
	var wg sync.WaitGroup
	for i, it := range targets {
		wg.Add(1)
		go func() {
			defer wg.Done()
			out[i] = result{ID: it.ID}
			if msg, err := a.stopItem(it); err != nil {
				out[i].Error = err.Error()
			} else {
				out[i].Message = msg
			}
		}()
	}
	wg.Wait()
	results = append(results, out...)
	ok := true
	for _, r := range results {
		if r.Error != "" {
			ok = false
		}
	}
	resp := response{OK: ok, Results: results}
	if !ok {
		resp.Error = "some items could not be stopped"
	}
	return resp
}

func (a *agent) stopItem(it item) (string, error) {
	timeout := time.Duration(max(a.c.StopTimeout, 1)) * time.Second
	switch it.Kind {
	case "heavy":
		return stopProcessTree(a.c, it.pid, it.cgroup, timeout)
	case "ci":
		_, err := runOut(timeout+30*time.Second, a.c.Docker, "stop", "-t", strconv.Itoa(a.c.StopTimeout), it.ref)
		if err != nil {
			return "", err
		}
		return "container stopped (the runner reports the job as failed)", nil
	case "session":
		if _, err := runOut(30*time.Second, a.c.Loginctl, "terminate-session", it.ref); err != nil {
			return "", err
		}
		return "session terminated", nil
	case "unit":
		if _, err := runOut(3*time.Minute, a.c.Systemctl, "stop", it.ref); err != nil {
			return "", err
		}
		return "unit stopped", nil
	}
	return "", fmt.Errorf("unknown kind %q", it.Kind)
}

func alive(pid int) bool {
	return syscall.Kill(pid, 0) == nil
}

// stopProcessTree sends SIGTERM to pid and every process of the job cgroup,
// waits up to timeout, then kills what is left.
func stopProcessTree(c config, pid int, cgroup string, timeout time.Duration) (string, error) {
	if pid <= 1 {
		return "", errors.New("no process")
	}
	syscall.Kill(pid, syscall.SIGTERM)
	if cgroup != "" {
		for _, p := range cgroupPids(c.CgroupRoot, cgroup) {
			syscall.Kill(p, syscall.SIGTERM)
		}
	}
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if !alive(pid) && (cgroup == "" || len(cgroupPids(c.CgroupRoot, cgroup)) == 0) {
			return "stopped", nil
		}
		time.Sleep(200 * time.Millisecond)
	}
	if cgroup != "" {
		if err := os.WriteFile(filepath.Join(c.CgroupRoot, cgroup, "cgroup.kill"), []byte("1"), 0); err != nil && !errors.Is(err, os.ErrNotExist) {
			log.Printf("cgroup.kill %s: %v", cgroup, err)
		}
	}
	syscall.Kill(pid, syscall.SIGKILL)
	return "killed after " + timeout.String(), nil
}

func (a *agent) pause(who string) response {
	reason := fmt.Sprintf("paused by %s at %s", who, time.Now().Format("2006-01-02 15:04"))
	files := []string{a.c.PauseFile}
	if a.c.Heavy != nil && a.c.Heavy.PauseFile != "" {
		files = append(files, a.c.Heavy.PauseFile)
	}
	for _, f := range files {
		if err := os.WriteFile(f, []byte(reason+"\n"), 0o644); err != nil {
			return response{Error: err.Error()}
		}
	}
	var results []result
	ok := true
	for _, u := range a.c.PauseUnits {
		r := result{ID: "unit:" + u, Message: "stopped"}
		if _, err := runOut(3*time.Minute, a.c.Systemctl, "stop", u); err != nil {
			r.Message, r.Error, ok = "", err.Error(), false
		}
		results = append(results, r)
	}
	resp := response{OK: ok, Results: results, Message: "paused: new heavy jobs are refused until `attos-jobs resume` or a reboot"}
	if !ok {
		resp.Error = "some units could not be stopped"
	}
	return resp
}

func (a *agent) resume() response {
	files := []string{a.c.PauseFile}
	if a.c.Heavy != nil && a.c.Heavy.PauseFile != "" {
		files = append(files, a.c.Heavy.PauseFile)
	}
	for _, f := range files {
		if err := os.Remove(f); err != nil && !errors.Is(err, os.ErrNotExist) {
			return response{Error: err.Error()}
		}
	}
	var results []result
	ok := true
	for _, u := range a.c.PauseUnits {
		r := result{ID: "unit:" + u, Message: "started"}
		if _, err := runOut(3*time.Minute, a.c.Systemctl, "start", u); err != nil {
			r.Message, r.Error, ok = "", err.Error(), false
		}
		results = append(results, r)
	}
	resp := response{OK: ok, Results: results, Message: "resumed"}
	if !ok {
		resp.Error = "some units could not be started"
	}
	return resp
}

// leave ends the local sessions while a shutdown waits for remote work, so the
// desktop is not left open; it is refused when no shutdown is pending.
func (a *agent) leave() response {
	col := &collector{c: a.c}
	if !col.preparingForShutdown() {
		return response{Error: "no shutdown is pending"}
	}
	var results []result
	for _, id := range localSessions(a.c) {
		r := result{ID: "session:" + id, Message: "session terminated"}
		if _, err := runOut(30*time.Second, a.c.Loginctl, "terminate-session", id); err != nil {
			r.Message, r.Error = "", err.Error()
		}
		results = append(results, r)
	}
	return response{OK: true, Results: results}
}
