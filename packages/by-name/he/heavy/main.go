// heavy serializes memory-heavy commands per host, runs them under a memory
// limit with a high OOM score, and dispatches them to a larger host when one
// is reachable.
package main

import (
	"bufio"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"syscall"
	"time"
)

const version = "0.1.0"

const defaultConfigPath = "/etc/heavy/config.json"

// Exit codes besides the command's own.
const (
	exitUsage    = 2
	exitBusy     = 75 // EX_TEMPFAIL: --no-wait and the lock is held
	exitSSHError = 255
)

type remote struct {
	Name string `json:"name"`
	SSH  string `json:"ssh"`
}

type config struct {
	LockFile       string   `json:"lockFile"`
	OwnerFile      string   `json:"ownerFile"`
	MemoryHigh     string   `json:"memoryHigh"`
	MemoryMax      string   `json:"memoryMax"`
	OOMScoreAdjust int      `json:"oomScoreAdjust"`
	Remotes        []remote `json:"remotes"`
	RemoteDir      string   `json:"remoteDir"`
	Excludes       []string `json:"excludes"`
}

func defaultConfig() config {
	return config{
		LockFile:       "/run/heavy/lock",
		OwnerFile:      "/run/heavy/owner",
		MemoryHigh:     "4G",
		MemoryMax:      "6G",
		OOMScoreAdjust: 1000,
		RemoteDir:      ".cache/heavy",
		Excludes:       []string{".git", "target", "result", "node_modules", ".direnv", ".devenv"},
	}
}

// loadConfig reads path over the defaults. A missing file yields the defaults.
func loadConfig(path string) (config, error) {
	c := defaultConfig()
	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return c, nil
	}
	if err != nil {
		return c, err
	}
	if err := json.Unmarshal(data, &c); err != nil {
		return c, fmt.Errorf("%s: %w", path, err)
	}
	return c, nil
}

var sizeRE = regexp.MustCompile(`^([0-9]+[KMGT]?|infinity)$`)

func validSize(s string) bool { return sizeRE.MatchString(s) }

// highFromMax returns 85% of a systemd size, keeping the unit suffix.
func highFromMax(max string) string {
	if max == "infinity" {
		return "infinity"
	}
	unit := ""
	num := max
	if n := len(max); n > 0 && strings.ContainsRune("KMGT", rune(max[n-1])) {
		unit = max[n-1:]
		num = max[:n-1]
	}
	v, err := strconv.ParseUint(num, 10, 64)
	if err != nil {
		return max
	}
	scale := map[string]uint64{"": 1, "K": 1 << 10, "M": 1 << 20, "G": 1 << 30, "T": 1 << 40}[unit]
	return strconv.FormatUint(v*scale*85/100, 10)
}

// shellQuote quotes one argument for a POSIX shell.
func shellQuote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
}

func shellJoin(args []string) string {
	q := make([]string, len(args))
	for i, a := range args {
		q[i] = shellQuote(a)
	}
	return strings.Join(q, " ")
}

var envNameRE = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_]*$`)

// remoteDirName maps the local host and absolute working directory to a
// directory relative to the remote home.
func remoteDirName(base, host, cwd string) string {
	p := strings.TrimPrefix(strings.ReplaceAll(filepath.Clean(cwd), "/", "_"), "_")
	if p == "" {
		p = "root"
	}
	return filepath.Join(base, host, p)
}

type runOptions struct {
	mode    string // auto, local, remote
	remote  string
	noWait  bool
	memHigh string
	memMax  string
	env     []string
	command []string
}

func parseRun(args []string) (runOptions, error) {
	o := runOptions{mode: "auto"}
	if h := os.Getenv("HEAVY_HOST"); h == "local" {
		o.mode = "local"
	} else if h != "" {
		o.mode, o.remote = "remote", h
	}
	for i := 0; i < len(args); i++ {
		a := args[i]
		next := func() (string, error) {
			if i+1 >= len(args) {
				return "", fmt.Errorf("%s needs a value", a)
			}
			i++
			return args[i], nil
		}
		var err error
		switch {
		case a == "--":
			o.command = args[i+1:]
			i = len(args)
		case a == "--local":
			o.mode, o.remote = "local", ""
		case a == "--auto":
			o.mode, o.remote = "auto", ""
		case a == "--remote":
			o.mode = "remote"
			o.remote, err = next()
		case a == "--no-wait":
			o.noWait = true
		case a == "--mem-high":
			o.memHigh, err = next()
		case a == "--mem-max":
			o.memMax, err = next()
		case a == "--env":
			var v string
			v, err = next()
			if err == nil {
				name, _, ok := strings.Cut(v, "=")
				if !ok || !envNameRE.MatchString(name) {
					err = fmt.Errorf("--env needs NAME=VALUE with a shell variable name, got %q", v)
				}
				o.env = append(o.env, v)
			}
		default:
			err = fmt.Errorf("unknown option %q (put the command after --)", a)
		}
		if err != nil {
			return o, err
		}
	}
	if len(o.command) == 0 {
		return o, errors.New("no command given after --")
	}
	for _, s := range []string{o.memHigh, o.memMax} {
		if s != "" && !validSize(s) {
			return o, fmt.Errorf("invalid size %q (use 512M, 6G or infinity)", s)
		}
	}
	return o, nil
}

func logf(format string, a ...any) {
	fmt.Fprintf(os.Stderr, "heavy: "+format+"\n", a...)
}

// sshProbe runs `heavy status --json` on a remote; replaceable in tests.
var sshProbe = func(dest string) error {
	cmd := exec.Command("ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", dest, "heavy", "status", "--json")
	cmd.Stdout = io.Discard
	cmd.Stderr = io.Discard
	return cmd.Run()
}

// pickRemote returns the first reachable remote, or nil.
func pickRemote(remotes []remote) *remote {
	for i := range remotes {
		if sshProbe(remotes[i].SSH) == nil {
			return &remotes[i]
		}
	}
	return nil
}

func findRemote(c config, name string) (*remote, bool) {
	for i := range c.Remotes {
		if c.Remotes[i].Name == name {
			return &c.Remotes[i], true
		}
	}
	return nil, false
}

func cmdRun(c config, args []string) int {
	o, err := parseRun(args)
	if err != nil {
		logf("%v", err)
		return exitUsage
	}
	switch o.mode {
	case "local":
		return runLocal(c, o)
	case "remote":
		r, ok := findRemote(c, o.remote)
		if !ok {
			logf("unknown remote %q (configured: %s)", o.remote, remoteNames(c))
			return exitUsage
		}
		return runRemote(c, *r, o)
	default:
		if r := pickRemote(c.Remotes); r != nil {
			return runRemote(c, *r, o)
		}
		if len(c.Remotes) > 0 {
			logf("running locally (no remote reachable)")
		}
		return runLocal(c, o)
	}
}

func remoteNames(c config) string {
	var n []string
	for _, r := range c.Remotes {
		n = append(n, r.Name)
	}
	if len(n) == 0 {
		return "none"
	}
	return strings.Join(n, ", ")
}

func runRemote(c config, r remote, o runOptions) int {
	cwd, err := os.Getwd()
	if err != nil {
		logf("%v", err)
		return 1
	}
	host, _ := os.Hostname()
	dir := remoteDirName(c.RemoteDir, host, cwd)
	logf("running on %s (~/%s)", r.Name, dir)

	// Sync the working tree: tar locally, unpack into a fresh remote dir.
	tarArgs := []string{"-C", cwd}
	for _, e := range c.Excludes {
		tarArgs = append(tarArgs, "--exclude="+e)
	}
	tarArgs = append(tarArgs, "-cf", "-", ".")
	tar := exec.Command("tar", tarArgs...)
	q := shellQuote(dir)
	unpack := exec.Command("ssh", "-o", "BatchMode=yes", r.SSH,
		fmt.Sprintf("rm -rf ~/%s && mkdir -p ~/%s && tar -C ~/%s -xf -", q, q, q))
	pipe, err := tar.StdoutPipe()
	if err != nil {
		logf("%v", err)
		return 1
	}
	unpack.Stdin = pipe
	tar.Stderr, unpack.Stdout, unpack.Stderr = os.Stderr, os.Stderr, os.Stderr
	if err := tar.Start(); err != nil {
		logf("tar: %v", err)
		return 1
	}
	uerr := unpack.Run()
	terr := tar.Wait()
	if uerr != nil || terr != nil {
		logf("syncing to %s failed (tar: %v, ssh: %v)", r.Name, terr, uerr)
		if exitCode(uerr) == exitSSHError {
			return exitSSHError
		}
		return 1
	}

	// Run the command there under the remote's own lock and limits.
	remoteArgs := []string{"heavy", "run", "--local"}
	if o.noWait {
		remoteArgs = append(remoteArgs, "--no-wait")
	}
	if o.memHigh != "" {
		remoteArgs = append(remoteArgs, "--mem-high", o.memHigh)
	}
	if o.memMax != "" {
		remoteArgs = append(remoteArgs, "--mem-max", o.memMax)
	}
	remoteArgs = append(remoteArgs, "--")
	var env []string
	for _, kv := range o.env {
		name, value, _ := strings.Cut(kv, "=")
		env = append(env, name+"="+shellQuote(value))
	}
	line := fmt.Sprintf("cd ~/%s && ", q)
	if len(env) > 0 {
		line += "env " + strings.Join(env, " ") + " "
	}
	line += shellJoin(append(remoteArgs, o.command...))
	sshArgs := []string{"-o", "BatchMode=yes"}
	if isTerminal(os.Stdin) {
		sshArgs = append(sshArgs, "-t")
	}
	sshArgs = append(sshArgs, r.SSH, line)
	cmd := exec.Command("ssh", sshArgs...)
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
	code := runForwardingSignals(cmd)
	if code == exitSSHError {
		logf("remote connection lost")
	}
	return code
}

func isTerminal(f *os.File) bool {
	st, err := f.Stat()
	return err == nil && st.Mode()&os.ModeCharDevice != 0
}

type owner struct {
	PID     int    `json:"pid"`
	User    string `json:"user"`
	Host    string `json:"host"`
	Cwd     string `json:"cwd"`
	Command string `json:"command"`
	Since   string `json:"since"`
}

// acquire takes the host lock. It returns the open lock file (keep it open
// while running) or exitBusy when noWait is set and the lock is held.
func acquire(c config, noWait bool) (*os.File, int) {
	f, err := os.OpenFile(c.LockFile, os.O_RDWR|os.O_CREATE, 0o666)
	if err != nil {
		logf("cannot open lock %s: %v", c.LockFile, err)
		return nil, 1
	}
	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err == nil {
		return f, 0
	}
	who := "another job"
	if data, err := os.ReadFile(c.OwnerFile); err == nil {
		var ow owner
		if json.Unmarshal(data, &ow) == nil && ow.PID != 0 {
			who = fmt.Sprintf("%s pid %d (%s) since %s", ow.User, ow.PID, ow.Command, ow.Since)
		}
	}
	if noWait {
		logf("busy: %s", who)
		f.Close()
		return nil, exitBusy
	}
	logf("waiting for %s", who)
	if err := syscall.Flock(int(f.Fd()), syscall.LOCK_EX); err != nil {
		logf("lock: %v", err)
		f.Close()
		return nil, 1
	}
	return f, 0
}

func writeOwner(c config, command []string) {
	host, _ := os.Hostname()
	cwd, _ := os.Getwd()
	user := os.Getenv("USER")
	if user == "" {
		user = strconv.Itoa(os.Getuid())
	}
	data, _ := json.Marshal(owner{
		PID: os.Getpid(), User: user, Host: host, Cwd: cwd,
		Command: strings.Join(command, " "), Since: time.Now().Format(time.RFC3339),
	})
	if err := os.WriteFile(c.OwnerFile, data, 0o666); err != nil {
		logf("warning: cannot write %s: %v", c.OwnerFile, err)
	}
}

func clearOwner(c config) {
	if f, err := os.OpenFile(c.OwnerFile, os.O_WRONLY|os.O_TRUNC, 0); err == nil {
		f.Close()
	}
}

// systemdRunPrefix returns the systemd-run argv that wraps a command in a
// memory-limited scope, or nil when systemd-run cannot be used.
var systemdRunPrefix = func(high, max string) []string {
	args := []string{"systemd-run"}
	if os.Geteuid() != 0 {
		args = append(args, "--user")
	}
	args = append(args, "--scope", "--quiet", "--collect", "-p", "MemoryHigh="+high, "-p", "MemoryMax="+max, "--")
	probe := exec.Command(args[0], append(args[1:], "true")...)
	probe.Stdout, probe.Stderr = io.Discard, io.Discard
	if probe.Run() != nil {
		return nil
	}
	return args
}

func runLocal(c config, o runOptions) int {
	lock, code := acquire(c, o.noWait)
	if lock == nil {
		return code
	}
	defer lock.Close()
	writeOwner(c, o.command)
	defer clearOwner(c)

	if err := os.WriteFile("/proc/self/oom_score_adj", []byte(strconv.Itoa(c.OOMScoreAdjust)), 0); err != nil {
		logf("warning: cannot set oom_score_adj: %v", err)
	}
	high, max := c.MemoryHigh, c.MemoryMax
	if o.memMax != "" {
		max = o.memMax
		high = highFromMax(max)
	}
	if o.memHigh != "" {
		high = o.memHigh
	}
	argv := o.command
	if prefix := systemdRunPrefix(high, max); prefix != nil {
		argv = append(append([]string{}, prefix...), o.command...)
	} else {
		logf("systemd-run unavailable; running without a memory limit")
	}
	cmd := exec.Command(argv[0], argv[1:]...)
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
	if len(o.env) > 0 {
		cmd.Env = append(os.Environ(), o.env...)
	}
	start := time.Now()
	logf("start (MemoryHigh=%s MemoryMax=%s): %s", high, max, strings.Join(o.command, " "))
	code = runForwardingSignals(cmd)
	logf("done exit=%d in %s", code, time.Since(start).Round(time.Second))
	return code
}

// runForwardingSignals runs cmd, forwards INT/TERM/HUP to it and returns its
// exit code (128+signal when killed by a signal).
func runForwardingSignals(cmd *exec.Cmd) int {
	sigs := make(chan os.Signal, 4)
	signal.Notify(sigs, syscall.SIGINT, syscall.SIGTERM, syscall.SIGHUP)
	defer signal.Stop(sigs)
	if err := cmd.Start(); err != nil {
		logf("%v", err)
		return 127
	}
	done := make(chan struct{})
	go func() {
		for {
			select {
			case s := <-sigs:
				_ = cmd.Process.Signal(s)
			case <-done:
				return
			}
		}
	}()
	err := cmd.Wait()
	close(done)
	return exitCode(err)
}

func exitCode(err error) int {
	if err == nil {
		return 0
	}
	var ee *exec.ExitError
	if errors.As(err, &ee) {
		if ws, ok := ee.Sys().(syscall.WaitStatus); ok && ws.Signaled() {
			return 128 + int(ws.Signal())
		}
		return ee.ExitCode()
	}
	return 1
}

type status struct {
	Host         string `json:"host"`
	MemTotal     uint64 `json:"memTotal"`
	MemAvailable uint64 `json:"memAvailable"`
	SwapTotal    uint64 `json:"swapTotal"`
	SwapFree     uint64 `json:"swapFree"`
	Load1        string `json:"load1"`
	Busy         bool   `json:"busy"`
	Owner        *owner `json:"owner"`
}

func readMeminfo(r io.Reader) map[string]uint64 {
	m := map[string]uint64{}
	sc := bufio.NewScanner(r)
	for sc.Scan() {
		f := strings.Fields(sc.Text())
		if len(f) >= 2 {
			v, err := strconv.ParseUint(f[1], 10, 64)
			if err == nil {
				if len(f) >= 3 && f[2] == "kB" {
					v *= 1024
				}
				m[strings.TrimSuffix(f[0], ":")] = v
			}
		}
	}
	return m
}

func localStatus(c config) status {
	host, _ := os.Hostname()
	s := status{Host: host}
	if f, err := os.Open("/proc/meminfo"); err == nil {
		m := readMeminfo(f)
		f.Close()
		s.MemTotal, s.MemAvailable, s.SwapTotal, s.SwapFree = m["MemTotal"], m["MemAvailable"], m["SwapTotal"], m["SwapFree"]
	}
	if data, err := os.ReadFile("/proc/loadavg"); err == nil {
		if f := strings.Fields(string(data)); len(f) > 0 {
			s.Load1 = f[0]
		}
	}
	if f, err := os.OpenFile(c.LockFile, os.O_RDWR, 0); err == nil {
		if syscall.Flock(int(f.Fd()), syscall.LOCK_EX|syscall.LOCK_NB) == nil {
			syscall.Flock(int(f.Fd()), syscall.LOCK_UN)
		} else {
			s.Busy = true
			if data, err := os.ReadFile(c.OwnerFile); err == nil {
				var ow owner
				if json.Unmarshal(data, &ow) == nil && ow.PID != 0 {
					s.Owner = &ow
				}
			}
		}
		f.Close()
	}
	return s
}

func gib(b uint64) string { return fmt.Sprintf("%.1fGiB", float64(b)/(1<<30)) }

func (s status) line() string {
	state := "idle"
	if s.Busy {
		state = "busy"
		if s.Owner != nil {
			state = fmt.Sprintf("busy: %s pid %d (%s) since %s", s.Owner.User, s.Owner.PID, s.Owner.Command, s.Owner.Since)
		}
	}
	return fmt.Sprintf("%s: mem %s/%s available, swap %s/%s free, load %s, %s",
		s.Host, gib(s.MemAvailable), gib(s.MemTotal), gib(s.SwapFree), gib(s.SwapTotal), s.Load1, state)
}

func cmdStatus(c config, args []string) int {
	s := localStatus(c)
	if len(args) == 1 && args[0] == "--json" {
		json.NewEncoder(os.Stdout).Encode(s)
		return 0
	}
	if len(args) > 0 {
		logf("usage: heavy status [--json]")
		return exitUsage
	}
	fmt.Println(s.line())
	return 0
}

func cmdHosts(c config) int {
	fmt.Println("local " + localStatus(c).line())
	for _, r := range c.Remotes {
		cmd := exec.Command("ssh", "-o", "BatchMode=yes", "-o", "ConnectTimeout=5", r.SSH, "heavy", "status", "--json")
		out, err := cmd.Output()
		var s status
		if err != nil || json.Unmarshal(out, &s) != nil {
			fmt.Printf("%s unreachable\n", r.Name)
			continue
		}
		fmt.Printf("%s %s\n", r.Name, s.line())
	}
	return 0
}

const usage = `heavy: run memory-heavy commands one at a time per host, under a memory limit,
on a larger host when one is reachable.

usage:
  heavy run [--auto | --local | --remote NAME] [--no-wait] [--mem-high SIZE] [--mem-max SIZE]
            [--env NAME=VALUE]... -- COMMAND [ARGS...]
  heavy status [--json]
  heavy hosts
  heavy --version | help

run modes:
  --auto (default)  the first reachable remote from the configuration, otherwise local
  --local           this host: wait for the host lock, then run in a systemd scope with
                    MemoryHigh/MemoryMax and oom_score_adj 1000 (killed before system processes)
  --remote NAME     copy the working directory (without .git, target, result, ...) to
                    ~/.cache/heavy/<host>/<path> on NAME and run there under its lock
HEAVY_HOST=local or HEAVY_HOST=NAME selects the mode when no flag is given.

Remote runs suit checks, evaluations and tests; build outputs stay on the remote.
Use --local when the command must produce files here.

exit codes: the command's own; 2 usage error; 75 busy with --no-wait; 255 SSH failure.
configuration: /etc/heavy/config.json (or --config FILE before the subcommand).
`

func main() {
	args := os.Args[1:]
	cfgPath := defaultConfigPath
	if len(args) >= 2 && args[0] == "--config" {
		cfgPath, args = args[1], args[2:]
	}
	if len(args) == 0 {
		fmt.Fprint(os.Stderr, usage)
		os.Exit(exitUsage)
	}
	c, err := loadConfig(cfgPath)
	if err != nil {
		logf("%v", err)
		os.Exit(exitUsage)
	}
	switch args[0] {
	case "run":
		os.Exit(cmdRun(c, args[1:]))
	case "status":
		os.Exit(cmdStatus(c, args[1:]))
	case "hosts":
		os.Exit(cmdHosts(c))
	case "--version", "version":
		fmt.Println("heavy " + version)
	case "help", "--help", "-h":
		fmt.Print(usage)
	default:
		fmt.Fprint(os.Stderr, usage)
		os.Exit(exitUsage)
	}
}
