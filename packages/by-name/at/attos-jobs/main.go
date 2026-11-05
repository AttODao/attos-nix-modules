// attos-jobs lists and stops the work that other hosts run on this machine:
// heavy jobs, Forgejo Actions job containers, remote (SSH) login sessions and
// selected system units. A root agent collects the list into a status file
// that anyone can read and executes stop/pause requests that arrive on a
// group-restricted Unix socket.
package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"sort"
	"strings"
	"text/tabwriter"
	"time"
)

const version = "0.1.0"

const defaultConfigPath = "/etc/attos-jobs/config.json"

const (
	exitUsage  = 2
	exitFailed = 1
)

type heavyConfig struct {
	LockFile  string `json:"lockFile"`
	OwnerFile string `json:"ownerFile"`
	PauseFile string `json:"pauseFile"`
}

type config struct {
	StatusFile  string            `json:"statusFile"`
	Socket      string            `json:"socket"`
	SocketGroup string            `json:"socketGroup"`
	PauseFile   string            `json:"pauseFile"`
	IntervalSec int               `json:"intervalSec"`
	StopTimeout int               `json:"stopTimeoutSec"`
	MinAgeSec   int               `json:"minSessionAgeSec"`
	Heavy       *heavyConfig      `json:"heavy"`
	Docker      string            `json:"docker"`
	CIPatterns  []string          `json:"ciNamePatterns"`
	Units       []string          `json:"units"`
	PauseUnits  []string          `json:"pauseUnits"`
	OriginNames map[string]string `json:"originNames"`
	Systemctl   string            `json:"systemctl"`
	Loginctl    string            `json:"loginctl"`
	Busctl      string            `json:"busctl"`
	CgroupRoot  string            `json:"cgroupRoot"`
	ProcRoot    string            `json:"procRoot"`
}

func defaultConfig() config {
	return config{
		StatusFile:  "/run/attos-jobs/status.json",
		Socket:      "/run/attos-jobs/control.sock",
		SocketGroup: "attos-jobs",
		PauseFile:   "/run/attos-jobs/paused",
		IntervalSec: 5,
		StopTimeout: 10,
		MinAgeSec:   15,
		CIPatterns:  []string{`^(FORGEJO|GITEA)-ACTIONS-TASK-`},
		Systemctl:   "systemctl",
		Loginctl:    "loginctl",
		Busctl:      "busctl",
		CgroupRoot:  "/sys/fs/cgroup",
		ProcRoot:    "/proc",
	}
}

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

// item is one piece of remote-initiated work.
type item struct {
	ID        string `json:"id"`
	Kind      string `json:"kind"` // heavy, ci, session, unit
	Title     string `json:"title"`
	Detail    string `json:"detail,omitempty"`
	User      string `json:"user,omitempty"`
	Origin    string `json:"origin,omitempty"`
	State     string `json:"state,omitempty"`
	SinceUnix int64  `json:"sinceUnix,omitempty"`
	Memory    uint64 `json:"memory,omitempty"`

	// Agent-internal handles used to stop the item; never trusted from clients.
	pid    int
	cgroup string
	ref    string
}

type statusDoc struct {
	Version              string   `json:"version"`
	Host                 string   `json:"host"`
	UpdatedUnix          int64    `json:"updatedUnix"`
	Paused               bool     `json:"paused"`
	PausedBy             string   `json:"pausedBy,omitempty"`
	PreparingForShutdown bool     `json:"preparingForShutdown"`
	Items                []item   `json:"items"`
	Errors               []string `json:"errors,omitempty"`
}

func readStatus(c config) (statusDoc, error) {
	var s statusDoc
	data, err := os.ReadFile(c.StatusFile)
	if err != nil {
		return s, err
	}
	err = json.Unmarshal(data, &s)
	return s, err
}

func humanAge(since int64, now time.Time) string {
	if since == 0 {
		return "-"
	}
	d := now.Sub(time.Unix(since, 0))
	switch {
	case d < time.Minute:
		return fmt.Sprintf("%ds", int(d.Seconds()))
	case d < time.Hour:
		return fmt.Sprintf("%dm", int(d.Minutes()))
	case d < 48*time.Hour:
		return fmt.Sprintf("%dh%02dm", int(d.Hours()), int(d.Minutes())%60)
	default:
		return fmt.Sprintf("%dd", int(d.Hours()/24))
	}
}

func humanBytes(b uint64) string {
	if b == 0 {
		return "-"
	}
	const gib = 1 << 30
	if b < 1<<20 {
		return "<1M"
	}
	if b >= gib {
		return fmt.Sprintf("%.1fG", float64(b)/gib)
	}
	return fmt.Sprintf("%dM", b>>20)
}

func cmdList(c config, args []string) int {
	asJSON := false
	for _, a := range args {
		switch a {
		case "--json":
			asJSON = true
		default:
			fmt.Fprintln(os.Stderr, "usage: attos-jobs list [--json]")
			return exitUsage
		}
	}
	s, err := readStatus(c)
	if err != nil {
		fmt.Fprintf(os.Stderr, "attos-jobs: cannot read %s (is attos-jobs-agent running?): %v\n", c.StatusFile, err)
		return exitFailed
	}
	if asJSON {
		json.NewEncoder(os.Stdout).Encode(s)
		return 0
	}
	now := time.Now()
	if age := now.Sub(time.Unix(s.UpdatedUnix, 0)); age > time.Duration(3*max(c.IntervalSec, 1))*time.Second {
		fmt.Fprintf(os.Stderr, "attos-jobs: status is %s old; the agent may be stuck\n", age.Round(time.Second))
	}
	if s.Paused {
		fmt.Printf("paused: new heavy and CI jobs are refused (%s); `attos-jobs resume` to accept them again\n", s.PausedBy)
	}
	if s.PreparingForShutdown {
		fmt.Println("shutdown requested: waiting for the remote work below")
	}
	if len(s.Items) == 0 {
		fmt.Println("no remote work")
		return 0
	}
	items := append([]item(nil), s.Items...)
	sort.SliceStable(items, func(i, j int) bool { return items[i].SinceUnix < items[j].SinceUnix })
	w := tabwriter.NewWriter(os.Stdout, 0, 4, 2, ' ', 0)
	fmt.Fprintln(w, "ID\tFROM\tAGE\tMEM\tSTATE\tWHAT")
	for _, it := range items {
		what := it.Title
		if it.Detail != "" {
			what += ": " + it.Detail
		}
		from := it.Origin
		if it.User != "" {
			from = it.User + "@" + orDash(it.Origin)
		}
		fmt.Fprintf(w, "%s\t%s\t%s\t%s\t%s\t%s\n", it.ID, orDash(from), humanAge(it.SinceUnix, now),
			humanBytes(it.Memory), orDash(it.State), what)
	}
	w.Flush()
	for _, e := range s.Errors {
		fmt.Fprintln(os.Stderr, "attos-jobs: collector: "+e)
	}
	return 0
}

func orDash(s string) string {
	if s == "" {
		return "-"
	}
	return s
}

func cmdRequest(c config, op string, args []string) int {
	req := request{Op: op}
	switch op {
	case "stop":
		for _, a := range args {
			if a == "--all" {
				req.All = true
				continue
			}
			if strings.HasPrefix(a, "-") {
				fmt.Fprintf(os.Stderr, "attos-jobs: unknown option %q\n", a)
				return exitUsage
			}
			req.IDs = append(req.IDs, a)
		}
		if req.All == (len(req.IDs) > 0) {
			fmt.Fprintln(os.Stderr, "usage: attos-jobs stop ID... | attos-jobs stop --all")
			return exitUsage
		}
	default:
		if len(args) > 0 {
			fmt.Fprintf(os.Stderr, "usage: attos-jobs %s\n", op)
			return exitUsage
		}
	}
	resp, err := send(c, req)
	if err != nil {
		fmt.Fprintf(os.Stderr, "attos-jobs: %v\n", err)
		return exitFailed
	}
	for _, r := range resp.Results {
		if r.Error != "" {
			fmt.Printf("%s: failed: %s\n", r.ID, r.Error)
		} else {
			fmt.Printf("%s: %s\n", r.ID, r.Message)
		}
	}
	if resp.Message != "" {
		fmt.Println(resp.Message)
	}
	if !resp.OK {
		if resp.Error != "" {
			fmt.Fprintf(os.Stderr, "attos-jobs: %s\n", resp.Error)
		}
		return exitFailed
	}
	return 0
}

const usage = `attos-jobs: list and stop work that other hosts run here (heavy jobs, CI job
containers, remote login sessions, selected units).

usage:
  attos-jobs list [--json]      what runs now (read from the agent's status file)
  attos-jobs stop ID...         stop items by the ID shown in list
  attos-jobs stop --all         stop every item
  attos-jobs pause              refuse new heavy jobs and stop the CI runner(s)
  attos-jobs resume             accept new work again
  attos-jobs leave              while a shutdown waits for remote work, end the local
                                sessions now instead of after the grace period
  attos-jobs agent              run the root agent (systemd service)
  attos-jobs --version | help

stop, pause, resume and leave need membership in the agent's socket group.
configuration: /etc/attos-jobs/config.json (or --config FILE before the subcommand).
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
		fmt.Fprintf(os.Stderr, "attos-jobs: %v\n", err)
		os.Exit(exitUsage)
	}
	switch args[0] {
	case "list", "ls":
		os.Exit(cmdList(c, args[1:]))
	case "stop", "pause", "resume", "leave":
		os.Exit(cmdRequest(c, args[0], args[1:]))
	case "agent":
		os.Exit(runAgent(c))
	case "--version", "version":
		fmt.Println("attos-jobs " + version)
	case "help", "--help", "-h":
		fmt.Print(usage)
	default:
		fmt.Fprint(os.Stderr, usage)
		os.Exit(exitUsage)
	}
}
