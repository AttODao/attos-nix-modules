package main

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"testing"
	"time"
)

const adminHash = "$2b$10$abcdefghijklmnopqrstuuABCDEFGHIJKLMNOPQRSTUVWXYZ01234"

func credentials(t *testing.T, key string) string {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "daemon-key"), []byte(key+"\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	return dir
}

func readJSON(t *testing.T, file string) map[string]any {
	object, err := readObject(file)
	if err != nil {
		t.Fatal(err)
	}
	return object
}

func TestBootstrapMergesState(t *testing.T) {
	key := strings.Repeat("k", 32)
	cfg := settings{DataDir: t.TempDir(), ListenAddress: "127.0.0.1", Hostname: "mc.example.org", WebPort: 23333, DaemonPort: 24444}
	global := filepath.Join(cfg.DataDir, "daemon/data/Config/global.json")
	os.MkdirAll(filepath.Dir(global), 0o700)
	os.WriteFile(global, []byte(`{"keep":12345678901234567890,"port":1,"html":"<a>"}`), 0o600)
	creds := credentials(t, key)
	if err := bootstrap("daemon", cfg, creds); err != nil {
		t.Fatal(err)
	}
	raw, _ := os.ReadFile(global)
	for _, want := range []string{`"keep":12345678901234567890`, `"port":24444`, `"key":"` + key + `"`, `"html":"<a>"`, `"prefix":"/daemon/"`} {
		if !strings.Contains(string(raw), want) {
			t.Errorf("missing %s in %s", want, raw)
		}
	}
	if info, _ := os.Stat(global); info.Mode().Perm() != 0o600 {
		t.Fatalf("mode %v", info.Mode())
	}
	if err := bootstrap("web", cfg, creds); err != nil {
		t.Fatal(err)
	}
	node := readJSON(t, filepath.Join(cfg.DataDir, "web/data/RemoteServiceConfig/00000000000000000000000000000001.json"))
	mappings := node["remoteMappings"].([]any)
	if len(mappings) != 1 || node["apiKey"] != key {
		t.Fatalf("unexpected node %v", node)
	}
	web := readJSON(t, filepath.Join(cfg.DataDir, "web/data/SystemConfig/config.json"))
	if web["reverseProxyMode"] != true {
		t.Fatalf("unexpected web config %v", web)
	}
	if bootstrap("other", cfg, creds) == nil {
		t.Fatal("unknown component accepted")
	}
}

func TestBootstrapRejects(t *testing.T) {
	cfg := settings{DataDir: t.TempDir()}
	if bootstrap("daemon", cfg, credentials(t, "short")) == nil {
		t.Fatal("short key accepted")
	}
	key := strings.Repeat("k", 32)
	global := filepath.Join(cfg.DataDir, "daemon/data/Config/global.json")
	os.MkdirAll(filepath.Dir(global), 0o700)
	target := filepath.Join(cfg.DataDir, "target.json")
	os.WriteFile(target, []byte(`{}`), 0o600)
	os.Symlink(target, global)
	if bootstrap("daemon", cfg, credentials(t, key)) == nil {
		t.Fatal("state symlink followed")
	}
	os.Remove(global)
	os.WriteFile(global, []byte(`[]`), 0o600)
	if bootstrap("daemon", cfg, credentials(t, key)) == nil {
		t.Fatal("non-object state accepted")
	}
}

func TestInitialAdmin(t *testing.T) {
	key := strings.Repeat("k", 32)
	cfg := settings{DataDir: t.TempDir(), Standalone: true, InitialAdmin: true}
	creds := credentials(t, key)
	write := func(admin map[string]any) {
		raw, _ := json.Marshal(admin)
		os.WriteFile(filepath.Join(creds, "initial-admin"), raw, 0o600)
	}
	write(map[string]any{"userName": " ", "passWord": adminHash})
	if bootstrap("web", cfg, creds) == nil {
		t.Fatal("blank user accepted")
	}
	write(map[string]any{"userName": "admin\n", "passWord": adminHash})
	if bootstrap("web", cfg, creds) == nil {
		t.Fatal("control character accepted")
	}
	write(map[string]any{"userName": "admin", "passWord": "plain"})
	if bootstrap("web", cfg, creds) == nil {
		t.Fatal("plain password accepted")
	}
	write(map[string]any{"userName": "admin", "passWord": adminHash})
	if err := bootstrap("web", cfg, creds); err != nil {
		t.Fatal(err)
	}
	users := filepath.Join(cfg.DataDir, "web/data/User")
	entries, _ := os.ReadDir(users)
	if len(entries) != 1 {
		t.Fatalf("users: %v", entries)
	}
	user := readJSON(t, filepath.Join(users, entries[0].Name()))
	if user["userName"] != "admin" || user["permission"] != json.Number("10") || entries[0].Name() != user["uuid"].(string)+".json" {
		t.Fatalf("unexpected user %v", user)
	}
	// An existing user prevents creating another administrator.
	if err := bootstrap("web", cfg, creds); err != nil {
		t.Fatal(err)
	}
	if entries, _ := os.ReadDir(users); len(entries) != 1 {
		t.Fatal("second administrator created")
	}
}

func freePort(t *testing.T) int {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	return listener.Addr().(*net.TCPAddr).Port
}

type output struct {
	sync.Mutex
	text strings.Builder
}

func (o *output) Write(data []byte) (int, error) {
	o.Lock()
	defer o.Unlock()
	return o.text.Write(data)
}

func (o *output) String() string {
	o.Lock()
	defer o.Unlock()
	return o.text.String()
}

// Mirrors the module's systemd-tmpfiles layout for the packaged release.
func layout(t *testing.T, packageDir, dataDir string) {
	arch := "x64"
	if runtime.GOARCH == "arm64" {
		arch = "arm64"
	}
	for _, dir := range []string{"daemon/data", "daemon/logs", "daemon/lib", "web/data/User", "web/logs"} {
		if err := os.MkdirAll(filepath.Join(dataDir, dir), 0o700); err != nil {
			t.Fatal(err)
		}
	}
	for _, tool := range []string{"pty", "file_zip", "7z"} {
		name := tool + "_linux_" + arch
		if err := os.Symlink(filepath.Join(packageDir, "daemon/lib", name), filepath.Join(dataDir, "daemon/lib", name)); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.Symlink(filepath.Join(packageDir, "web/public"), filepath.Join(dataDir, "web/public")); err != nil {
		t.Fatal(err)
	}
}

// Smoke test of the bundled release: web/assets, daemon prefix, authenticated local node, no key logging.
func TestBundledReleaseSmoke(t *testing.T) {
	packageDir := os.Getenv("MCSMANAGER_PACKAGE")
	node, err := exec.LookPath("node")
	if packageDir == "" || err != nil {
		t.Skip("MCSMANAGER_PACKAGE or node unavailable")
	}
	for _, kind := range []string{"web", "daemon"} {
		if _, err := os.Stat(filepath.Join(packageDir, kind, "node_modules")); err == nil {
			t.Fatalf("%s bundles node_modules", kind)
		}
	}
	tmp := t.TempDir()
	random := make([]byte, 32)
	rand.Read(random)
	key := hex.EncodeToString(random)
	cfg := settings{DataDir: filepath.Join(tmp, "state"), ListenAddress: "127.0.0.1", Hostname: "localhost",
		WebPort: freePort(t), DaemonPort: freePort(t), Standalone: true}
	if cfg.WebPort == cfg.DaemonPort {
		t.Fatal("ports collide")
	}
	layout(t, packageDir, cfg.DataDir)
	creds := credentials(t, key)
	for _, kind := range []string{"daemon", "web"} {
		if err := bootstrap(kind, cfg, creds); err != nil {
			t.Fatal(err)
		}
	}
	logs := map[string]*output{"daemon": {}, "web": {}}
	var children []*exec.Cmd
	exited := make(chan string, 2)
	for _, kind := range []string{"daemon", "web"} {
		home := filepath.Join(tmp, kind+"-home")
		os.Mkdir(home, 0o700)
		child := exec.Command(node, filepath.Join(packageDir, kind, "app.js"))
		child.Dir = filepath.Join(cfg.DataDir, kind)
		// No host env/secrets/proxy settings; any Docker lookup targets a nonexistent temp socket.
		child.Env = []string{"HOME=" + home, "TMPDIR=" + tmp, "LANG=C.UTF-8", "DOCKER_HOST=unix://" + tmp + "/no-docker.sock"}
		child.Stdout, child.Stderr = logs[kind], logs[kind]
		child.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
		if err := child.Start(); err != nil {
			t.Fatal(err)
		}
		children = append(children, child)
		go func(kind string, child *exec.Cmd) { child.Wait(); exited <- kind }(kind, child)
	}
	defer func() {
		for _, child := range children {
			syscall.Kill(-child.Process.Pid, syscall.SIGTERM)
		}
		deadline := time.After(3 * time.Second)
		for range children {
			select {
			case <-exited:
			case <-deadline:
				for _, child := range children {
					syscall.Kill(-child.Process.Pid, syscall.SIGKILL)
				}
				return
			}
		}
	}()
	fail := func(format string, arguments ...any) {
		// Only fake test state exists, but still redact its key from diagnostics.
		combined := strings.ReplaceAll(logs["daemon"].String()+logs["web"].String(), key, "[redacted]")
		if len(combined) > 3000 {
			combined = combined[len(combined)-3000:]
		}
		t.Fatalf(format+"\n%s", append(arguments, combined)...)
	}
	client := &http.Client{Timeout: time.Second}
	get := func(target string) (int, string) {
		response, err := client.Get(target)
		if err != nil {
			return 0, ""
		}
		defer response.Body.Close()
		body, _ := io.ReadAll(response.Body)
		return response.StatusCode, string(body)
	}
	eventually := func(label string, check func() bool) {
		for range 100 {
			select {
			case kind := <-exited:
				fail("%s exited before %s", kind, label)
			default:
			}
			if check() {
				return
			}
			time.Sleep(100 * time.Millisecond)
		}
		fail("MCSManager test readiness timed out: %s", label)
	}
	daemonURL := "http://127.0.0.1:" + itoa(cfg.DaemonPort)
	webURL := "http://127.0.0.1:" + itoa(cfg.WebPort)
	eventually("daemon socket", func() bool {
		status, body := get(daemonURL + "/daemon/socket.io/?EIO=4&transport=polling")
		return status == http.StatusOK && strings.HasPrefix(body, `0{"sid":`)
	})
	eventually("web auth status", func() bool {
		status, body := get(webURL + "/api/auth/status")
		var parsed struct {
			Data      *struct{ IsInstall *bool } `json:"data"`
			IsInstall *bool                      `json:"isInstall"`
		}
		if status != http.StatusOK || json.Unmarshal([]byte(body), &parsed) != nil {
			return false
		}
		install := parsed.IsInstall
		if parsed.Data != nil {
			install = parsed.Data.IsInstall
		}
		return install != nil && !*install
	})
	status, page := get(webURL)
	if status != http.StatusOK {
		fail("web page status %d", status)
	}
	asset := regexp.MustCompile(`(?:src|href)="([^" ]*/assets/[^" ]+\.js)"`).FindStringSubmatch(page)
	if asset == nil {
		fail("Bundled frontend asset reference missing")
	}
	base, _ := url.Parse(webURL + "/")
	reference, _ := url.Parse(asset[1])
	if status, body := get(base.ResolveReference(reference).String()); status != http.StatusOK || len(body) <= 100 {
		fail("Bundled frontend asset not served")
	}
	eventually("key validation", func() bool { return strings.Contains(logs["web"].String(), "key validation successful") })
	// Check both captured stdio and the upstream file log, not just journald output.
	for _, kind := range []string{"web", "daemon"} {
		if strings.Contains(logs[kind].String(), key) {
			fail("Fake authentication key leaked to %s stdio", kind)
		}
		dir := filepath.Join(cfg.DataDir, kind, "logs")
		entries, _ := os.ReadDir(dir)
		for _, entry := range entries {
			content, _ := os.ReadFile(filepath.Join(dir, entry.Name()))
			if strings.Contains(string(content), key) {
				fail("Fake key leaked to %s file log", kind)
			}
		}
	}
}

func itoa(value int) string { return strconv.Itoa(value) }
