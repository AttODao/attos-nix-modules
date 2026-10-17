package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

func dockerFlags(name string, args []string, positional int) (dockerCLI, []string, error) {
	fs := flag.NewFlagSet(name, flag.ContinueOnError)
	docker := fs.String("docker", "docker", "docker CLI path")
	if err := fs.Parse(args); err != nil {
		return "", nil, err
	}
	if positional >= 0 && fs.NArg() != positional {
		return "", nil, fmt.Errorf("%s: expected %d arguments", name, positional)
	}
	return dockerCLI(*docker), fs.Args(), nil
}

func swarmState(d dockerCLI) (state, control string, err error) {
	out, err := d.output("info", "--format", "{{.Swarm.LocalNodeState}} {{.Swarm.ControlAvailable}}")
	if err != nil {
		return "", "", err
	}
	state, control, _ = strings.Cut(out, " ")
	return state, control, nil
}

func swarmManager(args []string) error {
	d, rest, err := dockerFlags("swarm manager", args, 2)
	if err != nil {
		return err
	}
	address, tokenFile := rest[0], rest[1]
	state, _, err := swarmState(d)
	if err != nil {
		return err
	}
	if state != "active" {
		// init prints the join token on stdout; run discards it.
		if err := d.run("swarm", "init", "--advertise-addr", address, "--data-path-addr", address); err != nil {
			return err
		}
	}
	if _, control, err := swarmState(d); err != nil {
		return err
	} else if control != "true" {
		return errors.New("existing Swarm node is not a manager; refusing to change its role")
	}
	token, err := d.output("swarm", "join-token", "-q", "worker")
	if err != nil || token == "" {
		return errors.New("could not read the Swarm worker join token")
	}
	return writeSecret(tokenFile, []byte(token+"\n"))
}

func swarmWorker(args []string) error {
	d, rest, err := dockerFlags("swarm worker", args, 2)
	if err != nil {
		return err
	}
	manager, tokenFile := rest[0], rest[1]
	state, control, err := swarmState(d)
	if err != nil {
		return err
	}
	if state == "active" {
		if control != "false" {
			return errors.New("existing Swarm node is not a worker; refusing to change its role")
		}
		return nil
	}
	data, err := os.ReadFile(tokenFile)
	if err != nil {
		return errors.New("could not read the Swarm join token")
	}
	token := strings.TrimSpace(string(data))
	if token == "" {
		return errors.New("empty Swarm join token")
	}
	return d.run("swarm", "join", "--token", token, manager)
}

// overlayFormat matches the metadata format the shell implementation checked.
const overlayFormat = "{{.Driver}} {{.Attachable}} {{.Scope}} {{range $key, $value := .Options}}{{$key}} {{end}}"

// encryptedOverlay reports whether inspect metadata describes an encrypted
// attachable Swarm overlay. Existing networks are never silently recreated.
func encryptedOverlay(metadata string) bool {
	fields := strings.Fields(metadata)
	if len(fields) < 3 || fields[0] != "overlay" || fields[1] != "true" || fields[2] != "swarm" {
		return false
	}
	for _, option := range fields[3:] {
		if option == "encrypted" {
			return true
		}
	}
	return false
}

func swarmNetwork(args []string) error {
	d, rest, err := dockerFlags("swarm network", args, -1)
	if err != nil {
		return err
	}
	if len(rest) < 1 {
		return errors.New("swarm network: MARKER_DIR is required")
	}
	marker, networks := rest[0], rest[1:]
	if err := os.MkdirAll(marker, 0o755); err != nil {
		return err
	}
	stale, _ := filepath.Glob(filepath.Join(marker, "backend-*"))
	for _, path := range append(stale, filepath.Join(marker, "ready")) {
		if err := os.Remove(path); err != nil && !errors.Is(err, os.ErrNotExist) {
			return err
		}
	}
	for _, network := range networks {
		if err := ensureOverlay(d, network); err != nil {
			return err
		}
		if err := touch(filepath.Join(marker, network)); err != nil {
			return err
		}
	}
	return touch(filepath.Join(marker, "ready"))
}

func ensureOverlay(d dockerCLI, network string) error {
	for attempt := 0; attempt < 30; attempt++ {
		if metadata, err := d.output("network", "inspect", "--format", overlayFormat, network); err == nil {
			if !encryptedOverlay(metadata) {
				return fmt.Errorf("existing %s must be an encrypted attachable overlay; migrate it explicitly", network)
			}
			return nil
		}
		// Swarm can reject creation briefly after init; retry until it settles.
		if d.run("network", "create", "--driver", "overlay", "--attachable", "--opt", "encrypted", network) == nil {
			return nil
		}
		time.Sleep(time.Second)
	}
	return fmt.Errorf("failed to ensure the %s overlay network", network)
}

func touch(path string) error {
	file, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		return err
	}
	return file.Close()
}

func validToken(body []byte) bool {
	return strings.HasPrefix(strings.Trim(string(body), "\r\n"), "SWMTKN-1-")
}

func httpClient(source string) (*http.Client, error) {
	dialer := &net.Dialer{Timeout: 2 * time.Second}
	if source != "" {
		ip := net.ParseIP(source)
		if ip == nil {
			return nil, errors.New("source address must be an IP address")
		}
		dialer.LocalAddr = &net.TCPAddr{IP: ip}
	}
	return &http.Client{
		Timeout:   2 * time.Second,
		Transport: &http.Transport{Proxy: nil, DialContext: dialer.DialContext},
	}, nil
}

// get returns the body of a 2xx response.
func get(ctx context.Context, client *http.Client, url string) ([]byte, error) {
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	response, err := client.Do(request)
	if err != nil {
		return nil, err
	}
	defer response.Body.Close()
	body, err := io.ReadAll(io.LimitReader(response.Body, 64<<10))
	if err != nil {
		return nil, err
	}
	if response.StatusCode/100 != 2 {
		return nil, fmt.Errorf("HTTP %d", response.StatusCode)
	}
	return body, nil
}

func swarmFetch(args []string) error {
	fs := flag.NewFlagSet("swarm fetch", flag.ContinueOnError)
	source := fs.String("source", "", "local source IP address")
	if err := fs.Parse(args); err != nil {
		return err
	}
	if fs.NArg() != 2 {
		return errors.New("swarm fetch: expected URL TOKEN_FILE")
	}
	url, tokenFile := fs.Arg(0), fs.Arg(1)
	client, err := httpClient(*source)
	if err != nil {
		return err
	}
	for attempt := 0; attempt < 60; attempt++ {
		if body, err := get(context.Background(), client, url); err == nil && validToken(body) {
			return writeSecret(tokenFile, body)
		}
		time.Sleep(2 * time.Second)
	}
	return errors.New("failed to fetch the Swarm worker token")
}

func swarmWait(args []string) error {
	d, rest, err := dockerFlags("swarm wait", args, -1)
	if err != nil {
		return err
	}
	if len(rest) < 1 || len(rest) > 2 {
		return errors.New("swarm wait: expected URL [NETWORK]")
	}
	client, _ := httpClient("")
	for attempt := 0; attempt < 60; attempt++ {
		if _, err := get(context.Background(), client, rest[0]); err == nil {
			if len(rest) == 2 {
				// Docker materializes remote attachable overlays on the first container
				// attachment; requiring local presence would deadlock fresh workers.
				if metadata, err := d.output("network", "inspect", "--format", overlayFormat, rest[1]); err == nil && !encryptedOverlay(metadata) {
					return fmt.Errorf("local %s is not an encrypted attachable Swarm overlay", rest[1])
				}
			}
			return nil
		}
		time.Sleep(2 * time.Second)
	}
	return errors.New("failed to confirm the service overlay network")
}

// readinessHandler exposes overlay readiness and, when token is set, the worker
// token. Source address restriction is enforced by systemd IPAddressAllow.
func readinessHandler(marker, token string) http.Handler {
	isFile := func(name string) bool {
		info, err := os.Stat(filepath.Join(marker, name))
		return err == nil && info.Mode().IsRegular()
	}
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store")
		if r.Method != http.MethodGet {
			http.Error(w, "", http.StatusMethodNotAllowed)
			return
		}
		var body []byte
		switch name, sub := strings.CutPrefix(r.URL.Path, "/networks-ready/"); {
		case token != "" && r.URL.Path == "/worker-token":
			data, err := os.ReadFile(token)
			if err != nil {
				http.Error(w, "", http.StatusServiceUnavailable)
				return
			}
			body = data
		case r.URL.Path == "/networks-ready" || (sub && validBackend(name)):
			if !isFile("ready") || (sub && !isFile(name)) {
				http.Error(w, "", http.StatusServiceUnavailable)
				return
			}
			body = []byte("ready\n")
		default:
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "text/plain")
		_, _ = w.Write(body)
	})
}

func validBackend(name string) bool {
	rest, ok := strings.CutPrefix(name, "backend-")
	if !ok || rest == "" {
		return false
	}
	for _, c := range rest {
		if !(c >= 'a' && c <= 'z' || c >= '0' && c <= '9' || c == '-') {
			return false
		}
	}
	return true
}

func swarmServe(args []string) error {
	fs := flag.NewFlagSet("swarm serve", flag.ContinueOnError)
	address := fs.String("address", "", "IP address to bind")
	port := fs.String("port", "", "TCP port to bind")
	marker := fs.String("marker", "", "overlay readiness marker directory")
	token := fs.String("token", "", "worker token file to serve at /worker-token")
	if err := fs.Parse(args); err != nil {
		return err
	}
	if *address == "" || *port == "" || *marker == "" || fs.NArg() != 0 {
		return errors.New("swarm serve: --address, --port and --marker are required")
	}
	server := &http.Server{
		Addr:              net.JoinHostPort(*address, *port),
		Handler:           readinessHandler(*marker, *token),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       5 * time.Second,
		WriteTimeout:      5 * time.Second,
		ErrorLog:          nil,
	}
	return server.ListenAndServe()
}
