package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"
)

// runOut runs a command with a timeout and returns its stdout. The error is
// returned too, but stdout is still useful when only part of a batch failed.
func runOut(timeout time.Duration, name string, args ...string) ([]byte, error) {
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	var stderr bytes.Buffer
	cmd := exec.CommandContext(ctx, name, args...)
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		msg := strings.TrimSpace(stderr.String())
		if msg != "" {
			err = fmt.Errorf("%s: %w: %s", name, err, firstLine(msg))
		} else {
			err = fmt.Errorf("%s: %w", name, err)
		}
	}
	return out, err
}

func firstLine(s string) string {
	if i := strings.IndexByte(s, '\n'); i >= 0 {
		return s[:i]
	}
	return s
}

// parseBlocks parses `systemctl show` / `loginctl show-session` output for
// several objects: KEY=VALUE lines, objects separated by blank lines.
func parseBlocks(out []byte) []map[string]string {
	var blocks []map[string]string
	cur := map[string]string{}
	sc := bufio.NewScanner(bytes.NewReader(out))
	sc.Buffer(make([]byte, 64*1024), 1024*1024)
	for sc.Scan() {
		line := sc.Text()
		if line == "" {
			if len(cur) > 0 {
				blocks = append(blocks, cur)
				cur = map[string]string{}
			}
			continue
		}
		if k, v, ok := strings.Cut(line, "="); ok {
			cur[k] = v
		}
	}
	if len(cur) > 0 {
		blocks = append(blocks, cur)
	}
	return blocks
}

// proc describes one process read from procfs.
type proc struct {
	pid    int
	ppid   int
	comm   string
	argv   []string
	cgroup string // cgroup v2 path relative to the cgroup root, e.g. /user.slice/...
}

func readProc(root string, pid int) (proc, bool) {
	p := proc{pid: pid}
	dir := filepath.Join(root, strconv.Itoa(pid))
	stat, err := os.ReadFile(filepath.Join(dir, "stat"))
	if err != nil {
		return p, false
	}
	// comm is in parentheses and may contain spaces; the fields after the last ')' are fixed.
	s := string(stat)
	open, closeIdx := strings.IndexByte(s, '('), strings.LastIndexByte(s, ')')
	if open < 0 || closeIdx < open {
		return p, false
	}
	p.comm = s[open+1 : closeIdx]
	fields := strings.Fields(s[closeIdx+1:])
	if len(fields) >= 2 {
		p.ppid, _ = strconv.Atoi(fields[1])
	}
	if cmdline, err := os.ReadFile(filepath.Join(dir, "cmdline")); err == nil {
		cmdline = bytes.TrimRight(cmdline, "\x00")
		if len(cmdline) > 0 {
			p.argv = strings.Split(string(cmdline), "\x00")
		}
	}
	if cg, err := os.ReadFile(filepath.Join(dir, "cgroup")); err == nil {
		for _, line := range strings.Split(string(cg), "\n") {
			if strings.HasPrefix(line, "0::") {
				p.cgroup = strings.TrimPrefix(line, "0::")
			}
		}
	}
	return p, true
}

func allProcs(root string) []proc {
	entries, err := os.ReadDir(root)
	if err != nil {
		return nil
	}
	var ps []proc
	for _, e := range entries {
		pid, err := strconv.Atoi(e.Name())
		if err != nil {
			continue
		}
		if p, ok := readProc(root, pid); ok {
			ps = append(ps, p)
		}
	}
	return ps
}

func cgroupMemory(root, cgroup string) uint64 {
	if cgroup == "" {
		return 0
	}
	data, err := os.ReadFile(filepath.Join(root, cgroup, "memory.current"))
	if err != nil {
		return 0
	}
	v, _ := strconv.ParseUint(strings.TrimSpace(string(data)), 10, 64)
	return v
}

func cgroupPids(root, cgroup string) []int {
	data, err := os.ReadFile(filepath.Join(root, cgroup, "cgroup.procs"))
	if err != nil {
		return nil
	}
	var pids []int
	for _, f := range strings.Fields(string(data)) {
		if pid, err := strconv.Atoi(f); err == nil {
			pids = append(pids, pid)
		}
	}
	return pids
}

var sessionScopeRE = regexp.MustCompile(`/session-([0-9A-Za-z]+)\.scope$`)

// sessionOf returns the logind session ID whose scope contains the cgroup.
func sessionOf(cgroup string) string {
	if m := sessionScopeRE.FindStringSubmatch(cgroup); m != nil {
		return m[1]
	}
	return ""
}

func isHeavyRun(p proc) bool {
	return len(p.argv) >= 2 && filepath.Base(p.argv[0]) == "heavy" && p.argv[1] == "run"
}

// heavyCommand returns the command after `--` in a heavy run argv.
func heavyCommand(argv []string) string {
	for i, a := range argv {
		if a == "--" {
			return strings.Join(argv[i+1:], " ")
		}
	}
	return strings.Join(argv, " ")
}

// heavyRemoteDir splits a job directory that heavy copied from another host,
// ~/.cache/heavy/<sender>/<path with / turned into _>, into the sender and the
// last path component.
func heavyRemoteDir(cwd string) (sender, project string) {
	const marker = "/.cache/heavy/"
	i := strings.Index(cwd, marker)
	if i < 0 {
		return "", ""
	}
	sender, encoded, ok := strings.Cut(cwd[i+len(marker):], "/")
	if !ok || sender == "" || encoded == "" {
		return "", ""
	}
	encoded, _, _ = strings.Cut(encoded, "/")
	if j := strings.LastIndexByte(encoded, '_'); j >= 0 && j < len(encoded)-1 {
		encoded = encoded[j+1:]
	}
	return sender, encoded
}

func truncate(s string, n int) string {
	r := []rune(s)
	if len(r) <= n {
		return s
	}
	return string(r[:n-1]) + "…"
}

type heavyOwner struct {
	PID     int    `json:"pid"`
	User    string `json:"user"`
	Cwd     string `json:"cwd"`
	Command string `json:"command"`
	Since   string `json:"since"`
}

type session struct {
	id, user, uid, remoteHost, class, state, scope, service string
	remote                                                  bool
	since                                                   int64
}

type collector struct {
	c        config
	now      time.Time
	bootUnix float64
	procs    []proc
	byPID    map[int]proc
	sessions map[string]session
	errors   []string
}

func newCollector(c config) *collector {
	col := &collector{c: c, now: time.Now(), byPID: map[int]proc{}, sessions: map[string]session{}}
	if data, err := os.ReadFile(filepath.Join(c.ProcRoot, "uptime")); err == nil {
		if f := strings.Fields(string(data)); len(f) > 0 {
			up, _ := strconv.ParseFloat(f[0], 64)
			col.bootUnix = float64(col.now.UnixNano())/1e9 - up
		}
	}
	col.procs = allProcs(c.ProcRoot)
	for _, p := range col.procs {
		col.byPID[p.pid] = p
	}
	return col
}

func (col *collector) fail(format string, a ...any) {
	col.errors = append(col.errors, fmt.Sprintf(format, a...))
}

func (col *collector) origin(host string) string {
	if n, ok := col.c.OriginNames[host]; ok {
		return n
	}
	return host
}

func (col *collector) monotonicToUnix(usec string) int64 {
	v, err := strconv.ParseInt(usec, 10, 64)
	if err != nil || v == 0 || col.bootUnix == 0 {
		return 0
	}
	return int64(col.bootUnix + float64(v)/1e6)
}

func (col *collector) loadSessions() {
	out, err := runOut(10*time.Second, col.c.Loginctl, "list-sessions", "--no-legend", "--no-pager")
	if err != nil {
		col.fail("sessions: %v", err)
		return
	}
	var ids []string
	for _, line := range strings.Split(string(out), "\n") {
		if f := strings.Fields(line); len(f) > 0 {
			ids = append(ids, f[0])
		}
	}
	if len(ids) == 0 {
		return
	}
	args := []string{"show-session", "--no-pager", "-p", "Id", "-p", "Name", "-p", "User", "-p", "Remote", "-p", "RemoteHost",
		"-p", "Class", "-p", "State", "-p", "Scope", "-p", "Service", "-p", "TimestampMonotonic"}
	out, err = runOut(10*time.Second, col.c.Loginctl, append(args, ids...)...)
	if err != nil && len(out) == 0 {
		col.fail("sessions: %v", err)
		return
	}
	for _, b := range parseBlocks(out) {
		s := session{
			id: b["Id"], user: b["Name"], uid: b["User"], remoteHost: b["RemoteHost"], class: b["Class"],
			state: b["State"], scope: b["Scope"], service: b["Service"], remote: b["Remote"] == "yes",
			since: col.monotonicToUnix(b["TimestampMonotonic"]),
		}
		if s.id != "" {
			col.sessions[s.id] = s
		}
	}
}

func (s session) cgroup() string {
	if s.scope == "" || s.uid == "" {
		return ""
	}
	return "/user.slice/user-" + s.uid + ".slice/" + s.scope
}

func (col *collector) heavyItems() (items []item, heavySessions map[string]bool) {
	heavySessions = map[string]bool{}
	h := col.c.Heavy
	if h == nil {
		return nil, heavySessions
	}
	var ow heavyOwner
	if data, err := os.ReadFile(h.OwnerFile); err == nil && len(bytes.TrimSpace(data)) > 0 {
		if err := json.Unmarshal(data, &ow); err != nil {
			col.fail("heavy owner %s: %v", h.OwnerFile, err)
		}
	}
	for _, p := range col.procs {
		if !isHeavyRun(p) {
			continue
		}
		sid := sessionOf(p.cgroup)
		if sid != "" {
			heavySessions[sid] = true
		}
		it := item{ID: fmt.Sprintf("heavy:%d", p.pid), Kind: "heavy", pid: p.pid, State: "waiting"}
		it.Title = "heavy"
		it.Detail = truncate(heavyCommand(p.argv), 160)
		if s, ok := col.sessions[sid]; ok {
			it.User = s.user
			if s.remote {
				it.Origin = col.origin(s.remoteHost)
			}
			it.SinceUnix = s.since
		}
		if p.pid == ow.PID {
			it.State = "running"
			if ow.Command != "" {
				it.Detail = truncate(ow.Command, 160)
			}
			if ow.User != "" {
				it.User = ow.User
			}
			if t, err := time.Parse(time.RFC3339, ow.Since); err == nil {
				it.SinceUnix = t.Unix()
			}
			if sender, project := heavyRemoteDir(ow.Cwd); sender != "" {
				it.Origin = sender
				it.Title = "heavy (" + project + ")"
			} else if ow.Cwd != "" {
				it.Title = "heavy (" + filepath.Base(ow.Cwd) + ")"
			}
			// The job runs in the scope of the child systemd-run started.
			for _, child := range col.procs {
				if child.ppid == p.pid && child.cgroup != "" && child.cgroup != p.cgroup {
					it.cgroup = child.cgroup
					it.Memory = cgroupMemory(col.c.CgroupRoot, child.cgroup)
					break
				}
			}
		}
		items = append(items, it)
	}
	return items, heavySessions
}

type dockerPS struct {
	ID        string `json:"ID"`
	Names     string `json:"Names"`
	Image     string `json:"Image"`
	CreatedAt string `json:"CreatedAt"`
	State     string `json:"State"`
	Status    string `json:"Status"`
}

var ciNameRE = regexp.MustCompile(`TASK-([0-9]+)_WORKFLOW-(.*)_JOB-(.*)$`)

func ciTitle(name string) (title, detail string) {
	if m := ciNameRE.FindStringSubmatch(name); m != nil {
		return "CI " + m[2] + " / " + m[3], "task " + m[1]
	}
	return "CI container", name
}

func (col *collector) ciItems() []item {
	if col.c.Docker == "" || len(col.c.CIPatterns) == 0 {
		return nil
	}
	var res []*regexp.Regexp
	for _, p := range col.c.CIPatterns {
		re, err := regexp.Compile(p)
		if err != nil {
			col.fail("ci pattern %q: %v", p, err)
			continue
		}
		res = append(res, re)
	}
	out, err := runOut(15*time.Second, col.c.Docker, "ps", "--no-trunc", "--format", "{{json .}}")
	if err != nil {
		col.fail("ci: %v", err)
		return nil
	}
	var items []item
	for _, line := range strings.Split(string(out), "\n") {
		if strings.TrimSpace(line) == "" {
			continue
		}
		var d dockerPS
		if json.Unmarshal([]byte(line), &d) != nil {
			continue
		}
		matched := false
		for _, re := range res {
			if re.MatchString(d.Names) {
				matched = true
				break
			}
		}
		if !matched {
			continue
		}
		title, detail := ciTitle(d.Names)
		it := item{ID: "ci:" + shortID(d.ID), Kind: "ci", Title: title, Detail: detail + ", " + d.Image,
			Origin: "forgejo", State: d.State, ref: d.ID}
		if t, err := time.Parse("2006-01-02 15:04:05 -0700 MST", d.CreatedAt); err == nil {
			it.SinceUnix = t.Unix()
		}
		it.cgroup = "/system.slice/docker-" + d.ID + ".scope"
		it.Memory = cgroupMemory(col.c.CgroupRoot, it.cgroup)
		items = append(items, it)
	}
	return items
}

func shortID(id string) string {
	if len(id) > 12 {
		return id[:12]
	}
	return id
}

func (col *collector) sessionItems(skip map[string]bool) []item {
	var items []item
	for _, s := range col.sessions {
		if !s.remote || !strings.HasPrefix(s.class, "user") || skip[s.id] {
			continue
		}
		// Skip short probes such as `ssh host heavy status`.
		if s.since != 0 && col.now.Unix()-s.since < int64(col.c.MinAgeSec) {
			continue
		}
		it := item{ID: "session:" + s.id, Kind: "session", User: s.user, Origin: col.origin(s.remoteHost),
			State: s.state, SinceUnix: s.since, ref: s.id}
		it.Title = "remote session"
		if s.service != "" {
			it.Title = s.service + " session"
		}
		cg := s.cgroup()
		it.cgroup = cg
		it.Memory = cgroupMemory(col.c.CgroupRoot, cg)
		var cmds []string
		seen := map[string]bool{}
		for _, pid := range cgroupPids(col.c.CgroupRoot, cg) {
			p, ok := col.byPID[pid]
			if !ok || strings.HasPrefix(p.comm, "sshd") || len(p.argv) == 0 {
				continue
			}
			cmd := truncate(strings.Join(p.argv, " "), 80)
			if !seen[cmd] {
				seen[cmd] = true
				cmds = append(cmds, cmd)
			}
		}
		sort.Strings(cmds)
		if len(cmds) > 3 {
			cmds = append(cmds[:3], fmt.Sprintf("+%d more", len(cmds)-3))
		}
		it.Detail = strings.Join(cmds, "; ")
		items = append(items, it)
	}
	return items
}

func (col *collector) unitItems() []item {
	if len(col.c.Units) == 0 {
		return nil
	}
	args := []string{"show", "--no-pager", "--timestamp=unix", "-p", "Id", "-p", "Description", "-p", "ActiveState",
		"-p", "SubState", "-p", "ActiveEnterTimestamp", "-p", "ControlGroup"}
	out, err := runOut(10*time.Second, col.c.Systemctl, append(args, col.c.Units...)...)
	if err != nil && len(out) == 0 {
		col.fail("units: %v", err)
		return nil
	}
	var items []item
	for _, b := range parseBlocks(out) {
		switch b["ActiveState"] {
		case "active", "activating", "reloading", "deactivating":
		default:
			continue
		}
		it := item{ID: "unit:" + b["Id"], Kind: "unit", Title: b["Description"], Detail: b["Id"],
			State: b["ActiveState"] + "/" + b["SubState"], ref: b["Id"], cgroup: b["ControlGroup"]}
		if it.Title == "" {
			it.Title = b["Id"]
		}
		if ts := strings.TrimPrefix(b["ActiveEnterTimestamp"], "@"); ts != "" {
			it.SinceUnix, _ = strconv.ParseInt(ts, 10, 64)
		}
		it.Memory = cgroupMemory(col.c.CgroupRoot, it.cgroup)
		items = append(items, it)
	}
	return items
}

func (col *collector) preparingForShutdown() bool {
	out, err := runOut(5*time.Second, col.c.Busctl, "get-property", "org.freedesktop.login1", "/org/freedesktop/login1",
		"org.freedesktop.login1.Manager", "PreparingForShutdown")
	if err != nil {
		col.fail("PreparingForShutdown: %v", err)
		return false
	}
	return strings.TrimSpace(string(out)) == "b true"
}

// collect builds the full status document.
func collect(c config) statusDoc {
	col := newCollector(c)
	col.loadSessions()
	host, _ := os.Hostname()
	doc := statusDoc{Version: version, Host: host, UpdatedUnix: col.now.Unix(), Items: []item{}}
	if data, err := os.ReadFile(c.PauseFile); err == nil {
		doc.Paused = true
		doc.PausedBy = strings.TrimSpace(string(data))
	}
	doc.PreparingForShutdown = col.preparingForShutdown()
	heavy, heavySessions := col.heavyItems()
	doc.Items = append(doc.Items, heavy...)
	doc.Items = append(doc.Items, col.ciItems()...)
	doc.Items = append(doc.Items, col.sessionItems(heavySessions)...)
	doc.Items = append(doc.Items, col.unitItems()...)
	sort.SliceStable(doc.Items, func(i, j int) bool {
		if doc.Items[i].Kind != doc.Items[j].Kind {
			return kindOrder(doc.Items[i].Kind) < kindOrder(doc.Items[j].Kind)
		}
		return doc.Items[i].SinceUnix < doc.Items[j].SinceUnix
	})
	doc.Errors = col.errors
	return doc
}

func kindOrder(k string) int {
	switch k {
	case "heavy":
		return 0
	case "ci":
		return 1
	case "session":
		return 2
	default:
		return 3
	}
}

// localSessions returns the IDs of local (non-remote) user sessions.
func localSessions(c config) []string {
	col := &collector{c: c, sessions: map[string]session{}}
	col.loadSessions()
	var ids []string
	for _, s := range col.sessions {
		if !s.remote && strings.HasPrefix(s.class, "user") {
			ids = append(ids, s.id)
		}
	}
	sort.Strings(ids)
	return ids
}
