package main

import (
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestParseBlocks(t *testing.T) {
	b := parseBlocks([]byte("Id=5\nRemote=yes\n\nId=9\nRemote=no\nRemoteHost=\n"))
	if len(b) != 2 || b[0]["Id"] != "5" || b[1]["Remote"] != "no" || b[1]["RemoteHost"] != "" {
		t.Fatalf("%v", b)
	}
}

func TestNames(t *testing.T) {
	if got := sessionOf("/user.slice/user-1001.slice/session-15.scope"); got != "15" {
		t.Errorf("sessionOf = %q", got)
	}
	if got := sessionOf("/user.slice/user-1001.slice/user@1001.service/app.slice/run-r1.scope"); got != "" {
		t.Errorf("sessionOf(user manager) = %q", got)
	}
	title, detail := ciTitle("FORGEJO-ACTIONS-TASK-812_WORKFLOW-check_JOB-eval-hosts")
	if title != "CI check / eval-hosts" || detail != "task 812" {
		t.Errorf("ciTitle = %q, %q", title, detail)
	}
	if got := heavyCommand([]string{"heavy", "run", "--local", "--", "cargo", "test"}); got != "cargo test" {
		t.Errorf("heavyCommand = %q", got)
	}
	if s, p := heavyRemoteDir("/home/hermes/.cache/heavy/hermes/var_lib_hermes_workspace_attos-mouse"); s != "hermes" || p != "attos-mouse" {
		t.Errorf("heavyRemoteDir = %q, %q", s, p)
	}
	if s, _ := heavyRemoteDir("/home/attodao/src/x"); s != "" {
		t.Errorf("local dir reported sender %q", s)
	}
	if got := truncate("abcdef", 4); got != "abc…" {
		t.Errorf("truncate = %q", got)
	}
}

func write(t *testing.T, path, content string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o755); err != nil {
		t.Fatal(err)
	}
}

func fakeProc(t *testing.T, root string, pid, ppid int, comm, cgroup string, argv ...string) {
	dir := filepath.Join(root, fmt.Sprint(pid))
	write(t, filepath.Join(dir, "stat"), fmt.Sprintf("%d (%s) S %d 1 1 0 -1\n", pid, comm, ppid))
	write(t, filepath.Join(dir, "cmdline"), strings.Join(argv, "\x00")+"\x00")
	write(t, filepath.Join(dir, "cgroup"), "0::"+cgroup+"\n")
}

// fixture builds a fake procfs, cgroup tree and fake loginctl/busctl/docker/systemctl.
func fixture(t *testing.T) config {
	dir := t.TempDir()
	c := defaultConfig()
	c.ProcRoot = filepath.Join(dir, "proc")
	c.CgroupRoot = filepath.Join(dir, "cgroup")
	c.StatusFile = filepath.Join(dir, "run", "status.json")
	c.Socket = filepath.Join(dir, "run", "control.sock")
	c.SocketGroup = ""
	c.PauseFile = filepath.Join(dir, "run", "paused")
	c.Heavy = &heavyConfig{OwnerFile: filepath.Join(dir, "heavy", "owner"), PauseFile: filepath.Join(dir, "heavy", "paused")}
	c.Units = []string{"strata-headless-iq3-s.service", "other.service"}
	c.OriginNames = map[string]string{"10.252.0.1": "hermes"}
	c.MinAgeSec = 15

	write(t, filepath.Join(c.ProcRoot, "uptime"), "1000.00 2000.00\n")
	heavyScope := "/user.slice/user-1001.slice/session-5.scope"
	jobScope := "/user.slice/user-1001.slice/user@1001.service/app.slice/run-r1.scope"
	fakeProc(t, c.ProcRoot, 100, 1, "heavy", heavyScope, "heavy", "run", "--local", "--", "cargo", "test")
	fakeProc(t, c.ProcRoot, 101, 100, "cargo", jobScope, "cargo", "test")
	fakeProc(t, c.ProcRoot, 200, 1, "heavy", heavyScope, "/run/current-system/sw/bin/heavy", "run", "--local", "--", "nix", "build")
	fakeProc(t, c.ProcRoot, 300, 1, "adb", "/user.slice/user-1001.slice/session-7.scope", "adb", "-L", "tcp:5037", "fork-server")
	fakeProc(t, c.ProcRoot, 301, 1, "sshd-session", "/user.slice/user-1001.slice/session-7.scope", "sshd-session: hermes")
	write(t, filepath.Join(c.CgroupRoot, jobScope, "memory.current"), "2147483648\n")
	write(t, filepath.Join(c.CgroupRoot, "user.slice/user-1001.slice/session-7.scope", "cgroup.procs"), "300\n301\n")
	write(t, filepath.Join(c.CgroupRoot, "user.slice/user-1001.slice/session-7.scope", "memory.current"), "1048576\n")
	write(t, c.Heavy.OwnerFile, `{"pid":100,"user":"hermes","cwd":"/home/hermes/.cache/heavy/hermes/x_attos-mouse","command":"cargo test","since":"2026-11-05T10:00:00+09:00"}`)

	bin := filepath.Join(dir, "bin")
	// Session 5 runs the heavy job, 7 is a leftover remote session, 8 is a fresh probe, 9 is local.
	write(t, filepath.Join(bin, "loginctl"), `#!/bin/sh
case "$1" in
list-sessions) printf '5 1001 hermes - 14574 user - no -\n7 1001 hermes - 14600 user - no -\n8 1001 hermes - 14700 user - no -\n9 1000 attodao seat0 251210 user tty1 no -\n' ;;
show-session) cat <<EOF
Id=5
Name=hermes
User=1001
Remote=yes
RemoteHost=10.252.0.1
Class=user
State=active
Scope=session-5.scope
Service=sshd
TimestampMonotonic=100000000

Id=7
Name=hermes
User=1001
Remote=yes
RemoteHost=10.252.0.1
Class=user
State=closing
Scope=session-7.scope
Service=sshd
TimestampMonotonic=200000000

Id=8
Name=hermes
User=1001
Remote=yes
RemoteHost=10.252.0.1
Class=user
State=active
Scope=session-8.scope
Service=sshd
TimestampMonotonic=999000000

Id=9
Name=attodao
User=1000
Remote=no
RemoteHost=
Class=user
State=active
Scope=session-9.scope
Service=greetd
TimestampMonotonic=50000000
EOF
;;
terminate-session) echo "$2" >> "`+dir+`/terminated" ;;
esac
`)
	write(t, filepath.Join(bin, "busctl"), "#!/bin/sh\necho 'b false'\n")
	write(t, filepath.Join(bin, "docker"), `#!/bin/sh
case "$1" in
ps) echo '{"ID":"0123456789abcdef0123","Names":"FORGEJO-ACTIONS-TASK-812_WORKFLOW-check_JOB-eval","Image":"node:24","CreatedAt":"2026-11-05 10:30:00 +0900 JST","State":"running","Status":"Up 5 minutes"}'
    echo '{"ID":"fedcba","Names":"strata-headless","Image":"strata","CreatedAt":"2026-11-05 09:00:00 +0900 JST","State":"running","Status":"Up"}' ;;
stop) echo "$4" >> "`+dir+`/docker-stopped" ;;
esac
`)
	write(t, filepath.Join(bin, "systemctl"), `#!/bin/sh
case "$1" in
show) printf 'Id=strata-headless-iq3-s.service\nDescription=Strata IQ3_S\nActiveState=active\nSubState=running\nActiveEnterTimestamp=@1793000000\nControlGroup=/system.slice/strata-headless-iq3-s.service\n\nId=other.service\nDescription=Other\nActiveState=inactive\nSubState=dead\nActiveEnterTimestamp=\nControlGroup=\n' ;;
*) echo "$1 $2" >> "`+dir+`/systemctl" ;;
esac
`)
	c.Loginctl = filepath.Join(bin, "loginctl")
	c.Busctl = filepath.Join(bin, "busctl")
	c.Docker = filepath.Join(bin, "docker")
	c.Systemctl = filepath.Join(bin, "systemctl")
	return c
}

func TestCollect(t *testing.T) {
	c := fixture(t)
	doc := collect(c)
	if len(doc.Errors) > 0 {
		t.Fatalf("errors: %v", doc.Errors)
	}
	got := map[string]item{}
	var ids []string
	for _, it := range doc.Items {
		got[it.ID] = it
		ids = append(ids, it.ID)
	}
	want := []string{"heavy:100", "heavy:200", "ci:0123456789ab", "session:7", "unit:strata-headless-iq3-s.service"}
	if strings.Join(ids, " ") != strings.Join(want, " ") {
		t.Fatalf("items %v, want %v", ids, want)
	}
	h := got["heavy:100"]
	if h.State != "running" || h.User != "hermes" || h.Origin != "hermes" || h.Detail != "cargo test" ||
		h.Memory != 2<<30 || h.cgroup == "" || h.Title != "heavy (attos-mouse)" {
		t.Errorf("running heavy: %+v", h)
	}
	if w := got["heavy:200"]; w.State != "waiting" || w.Detail != "nix build" || w.Origin != "hermes" {
		t.Errorf("waiting heavy: %+v", w)
	}
	if ci := got["ci:0123456789ab"]; ci.Title != "CI check / eval" || ci.SinceUnix == 0 || ci.State != "running" {
		t.Errorf("ci: %+v", ci)
	}
	if s := got["session:7"]; s.State != "closing" || s.Detail != "adb -L tcp:5037 fork-server" || s.Memory != 1<<20 || s.User != "hermes" {
		t.Errorf("session: %+v", s)
	}
	if u := got["unit:strata-headless-iq3-s.service"]; u.Title != "Strata IQ3_S" || u.SinceUnix != 1793000000 {
		t.Errorf("unit: %+v", u)
	}
	if ids := localSessions(c); strings.Join(ids, ",") != "9" {
		t.Errorf("local sessions %v", ids)
	}
}

func TestAgentRequests(t *testing.T) {
	c := fixture(t)
	c.PauseUnits = []string{"forgejo-runner-default.service"}
	if err := os.MkdirAll(filepath.Dir(c.Socket), 0o755); err != nil {
		t.Fatal(err)
	}
	ln, err := listen(c)
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()
	a := &agent{c: c}
	go func() {
		for {
			conn, err := ln.Accept()
			if err != nil {
				return
			}
			go a.serve(conn.(*net.UnixConn))
		}
	}()

	resp, err := send(c, request{Op: "pause"})
	if err != nil || !resp.OK {
		t.Fatalf("pause: %+v %v", resp, err)
	}
	for _, f := range []string{c.PauseFile, c.Heavy.PauseFile} {
		if data, err := os.ReadFile(f); err != nil || !strings.Contains(string(data), "paused by") {
			t.Errorf("%s: %q %v", f, data, err)
		}
	}
	if s, err := readStatus(c); err != nil || !s.Paused {
		t.Errorf("status after pause: %+v %v", s, err)
	}
	resp, err = send(c, request{Op: "resume"})
	if err != nil || !resp.OK {
		t.Fatalf("resume: %+v %v", resp, err)
	}
	if _, err := os.Stat(c.PauseFile); !os.IsNotExist(err) {
		t.Errorf("pause file left: %v", err)
	}
	log, _ := os.ReadFile(filepath.Join(filepath.Dir(c.ProcRoot), "systemctl"))
	if string(log) != "stop forgejo-runner-default.service\nstart forgejo-runner-default.service\n" {
		t.Errorf("systemctl calls: %q", log)
	}

	resp, err = send(c, request{Op: "stop", IDs: []string{"session:7", "ci:0123456789ab", "unit:strata-headless-iq3-s.service", "heavy:999"}})
	if err != nil {
		t.Fatal(err)
	}
	if resp.OK || len(resp.Results) != 4 || resp.Results[0].ID != "heavy:999" || resp.Results[0].Error == "" {
		t.Fatalf("stop: %+v", resp)
	}
	root := filepath.Dir(c.ProcRoot)
	// Session 7 is closing: logind would ignore terminate-session, so its scope is stopped.
	if data, _ := os.ReadFile(filepath.Join(root, "terminated")); len(data) != 0 {
		t.Errorf("terminate-session called for a closing session: %q", data)
	}
	if data, _ := os.ReadFile(filepath.Join(root, "systemctl")); !strings.Contains(string(data), "stop session-7.scope\n") {
		t.Errorf("systemctl calls %q, want stop session-7.scope", data)
	}
	if data, _ := os.ReadFile(filepath.Join(root, "docker-stopped")); string(data) != "0123456789abcdef0123\n" {
		t.Errorf("docker stop %q", data)
	}

	if resp, err := send(c, request{Op: "leave"}); err != nil || resp.OK {
		t.Errorf("leave without a pending shutdown: %+v %v", resp, err)
	}
	if resp, err := send(c, request{Op: "bogus"}); err != nil || resp.OK {
		t.Errorf("bogus op: %+v %v", resp, err)
	}
}

func TestStopProcessTree(t *testing.T) {
	c := defaultConfig()
	cmd := exec.Command("sleep", "60")
	if err := cmd.Start(); err != nil {
		t.Skip(err)
	}
	done := make(chan struct{})
	go func() { cmd.Wait(); close(done) }()
	msg, err := stopProcessTree(c, cmd.Process.Pid, "", 5*time.Second)
	<-done
	if err != nil || msg != "stopped" {
		t.Fatalf("%q %v", msg, err)
	}
	// A process that ignores SIGTERM is killed after the timeout.
	cmd = exec.Command("sh", "-c", "trap '' TERM; sleep 60")
	if err := cmd.Start(); err != nil {
		t.Skip(err)
	}
	done = make(chan struct{})
	go func() { cmd.Wait(); close(done) }()
	time.Sleep(200 * time.Millisecond)
	msg, err = stopProcessTree(c, cmd.Process.Pid, "", time.Second)
	<-done
	if err != nil || !strings.HasPrefix(msg, "killed") {
		t.Fatalf("%q %v", msg, err)
	}
}

func TestHumanAge(t *testing.T) {
	now := time.Unix(10000, 0)
	for since, want := range map[int64]string{0: "-", 9990: "10s", 9000: "16m", 2800: "2h00m", 10000 - 3*86400: "3d"} {
		if got := humanAge(since, now); got != want {
			t.Errorf("humanAge(%d) = %q, want %q", since, got, want)
		}
	}
}
