package main

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
)

func TestShellQuote(t *testing.T) {
	cases := map[string]string{
		"":          "''",
		"a b":       "'a b'",
		"it's":      `'it'\''s'`,
		"$HOME":     "'$HOME'",
		"line\nend": "'line\nend'",
	}
	for in, want := range cases {
		if got := shellQuote(in); got != want {
			t.Errorf("shellQuote(%q) = %q, want %q", in, got, want)
		}
	}
	if got := shellJoin([]string{"nix", "eval", "a b"}); got != "'nix' 'eval' 'a b'" {
		t.Errorf("shellJoin = %q", got)
	}
}

func TestRemoteDirName(t *testing.T) {
	got := remoteDirName(".cache/heavy", "hermes", "/var/lib/hermes/workspace/x/")
	if got != ".cache/heavy/hermes/var_lib_hermes_workspace_x" {
		t.Errorf("got %q", got)
	}
	if got := remoteDirName(".cache/heavy", "h", "/"); got != ".cache/heavy/h/root" {
		t.Errorf("root: got %q", got)
	}
}

func TestLoadConfig(t *testing.T) {
	dir := t.TempDir()
	c, err := loadConfig(filepath.Join(dir, "missing.json"))
	if err != nil || c.MemoryMax != "6G" || len(c.Remotes) != 0 {
		t.Fatalf("missing file: %+v %v", c, err)
	}
	p := filepath.Join(dir, "c.json")
	os.WriteFile(p, []byte(`{"memoryMax":"48G","remotes":[{"name":"attodesk","ssh":"attodesk.example"}]}`), 0o644)
	c, err = loadConfig(p)
	if err != nil || c.MemoryMax != "48G" || c.MemoryHigh != "4G" || c.Remotes[0].SSH != "attodesk.example" {
		t.Fatalf("file: %+v %v", c, err)
	}
	os.WriteFile(p, []byte(`{`), 0o644)
	if _, err := loadConfig(p); err == nil {
		t.Fatal("invalid JSON accepted")
	}
}

func TestSizes(t *testing.T) {
	for _, s := range []string{"512M", "6G", "1024", "infinity"} {
		if !validSize(s) {
			t.Errorf("%q rejected", s)
		}
	}
	for _, s := range []string{"", "6GB", "-1", "1.5G", "inf"} {
		if validSize(s) {
			t.Errorf("%q accepted", s)
		}
	}
	if got := highFromMax("10G"); got != "9126805504" {
		t.Errorf("highFromMax(10G) = %s", got)
	}
}

func TestParseRun(t *testing.T) {
	t.Setenv("HEAVY_HOST", "")
	o, err := parseRun([]string{"--remote", "attodesk", "--env", "A=b c", "--", "nix", "--", "x"})
	if err != nil || o.mode != "remote" || o.remote != "attodesk" || strings.Join(o.command, " ") != "nix -- x" || o.env[0] != "A=b c" {
		t.Fatalf("%+v %v", o, err)
	}
	if _, err := parseRun([]string{"--env", "1A=b", "--", "x"}); err == nil {
		t.Error("bad env name accepted")
	}
	if _, err := parseRun([]string{"--mem-max", "6GB", "--", "x"}); err == nil {
		t.Error("bad size accepted")
	}
	if _, err := parseRun([]string{"--local"}); err == nil {
		t.Error("missing command accepted")
	}
	t.Setenv("HEAVY_HOST", "local")
	if o, _ := parseRun([]string{"--", "x"}); o.mode != "local" {
		t.Errorf("HEAVY_HOST=local: %+v", o)
	}
	if o, _ := parseRun([]string{"--auto", "--", "x"}); o.mode != "auto" {
		t.Errorf("flag over env: %+v", o)
	}
}

func TestLockNoWait(t *testing.T) {
	dir := t.TempDir()
	c := defaultConfig()
	c.LockFile = filepath.Join(dir, "lock")
	c.OwnerFile = filepath.Join(dir, "owner")
	first, code := acquire(c, true)
	if first == nil || code != 0 {
		t.Fatalf("first acquire: %d", code)
	}
	defer first.Close()
	writeOwner(c, []string{"sleep", "1"})
	second, code := acquire(c, true)
	if second != nil || code != exitBusy {
		t.Fatalf("second acquire: %v %d", second, code)
	}
	if s := localStatus(c); !s.Busy || s.Owner == nil || s.Owner.Command != "sleep 1" {
		t.Fatalf("status: %+v", s)
	}
	syscall.Flock(int(first.Fd()), syscall.LOCK_UN)
	if s := localStatus(c); s.Busy {
		t.Fatal("still busy after unlock")
	}
}

func TestPickRemote(t *testing.T) {
	saved := sshProbe
	defer func() { sshProbe = saved }()
	remotes := []remote{{"a", "a.example"}, {"b", "b.example"}}
	sshProbe = func(dest string) error {
		if dest == "b.example" {
			return nil
		}
		return errors.New("unreachable")
	}
	if r := pickRemote(remotes); r == nil || r.Name != "b" {
		t.Fatalf("got %+v", r)
	}
	sshProbe = func(string) error { return errors.New("unreachable") }
	if r := pickRemote(remotes); r != nil {
		t.Fatalf("got %+v", r)
	}
	if r := pickRemote(nil); r != nil {
		t.Fatal("empty remotes")
	}
}

func TestMeminfo(t *testing.T) {
	m := readMeminfo(strings.NewReader("MemTotal:       12000 kB\nMemAvailable:    6000 kB\nHugePages_Total:       0\n"))
	if m["MemTotal"] != 12000*1024 || m["MemAvailable"] != 6000*1024 || m["HugePages_Total"] != 0 {
		t.Fatalf("%v", m)
	}
}

func TestExitCode(t *testing.T) {
	if exitCode(nil) != 0 {
		t.Error("nil")
	}
	if exitCode(errors.New("x")) != 1 {
		t.Error("plain error")
	}
}

func TestIsTerminal(t *testing.T) {
	null, err := os.Open("/dev/null")
	if err != nil {
		t.Skip(err)
	}
	defer null.Close()
	if isTerminal(null) {
		t.Error("/dev/null is a character device but not a terminal")
	}
	f, _ := os.CreateTemp(t.TempDir(), "x")
	defer f.Close()
	if isTerminal(f) {
		t.Error("regular file reported as a terminal")
	}
}

func TestPause(t *testing.T) {
	dir := t.TempDir()
	c := defaultConfig()
	c.LockFile = filepath.Join(dir, "lock")
	c.OwnerFile = filepath.Join(dir, "owner")
	if pausedReason(c) != "" {
		t.Fatal("no pause file configured but paused")
	}
	c.PauseFile = filepath.Join(dir, "paused")
	if pausedReason(c) != "" {
		t.Fatal("missing pause file but paused")
	}
	os.WriteFile(c.PauseFile, nil, 0o644)
	if pausedReason(c) != "paused" {
		t.Fatalf("empty pause file: %q", pausedReason(c))
	}
	os.WriteFile(c.PauseFile, []byte("attos-jobs pause by attodao\n"), 0o644)
	if got := pausedReason(c); got != "attos-jobs pause by attodao" {
		t.Fatalf("reason: %q", got)
	}
	if code := runLocal(c, runOptions{command: []string{"true"}}); code != exitBusy {
		t.Fatalf("paused host ran a job: exit %d", code)
	}
	if s := localStatus(c); s.Paused == "" || !strings.Contains(s.line(), "paused") {
		t.Fatalf("status does not report the pause: %+v", s)
	}
}
