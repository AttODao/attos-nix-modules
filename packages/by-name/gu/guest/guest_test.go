package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"slices"
	"testing"
)

const sampleConfig = `{
  "flake": "path:/srv",
  "guests": {
    "worker": {
      "type": "virtual-machine",
      "launchConfig": {"devices": {"gpu": {"type": "gpu", "pci": "0000:01:00.0", "productid": 1, "required": true}}},
      "managedDeviceNames": ["gpu"],
      "credentialUnit": "incus-guest-credentials-worker.service",
      "credentialFiles": {
        "/var/lib/worker/token.env": {"source": "/run/secrets/worker.env", "owner": "root", "group": "root", "mode": "0600"},
        "/home/dev/.app/app.env": {"source": "/run/secrets/app.env", "owner": "dev", "group": "users", "mode": "0640"}
      },
      "credentialRestartUnits": ["worker.service"]
    },
    "box": {"type": "container", "launchConfig": {}}
  }
}`

func testConfig(t *testing.T) *config {
	t.Helper()
	cfg, err := parseConfig([]byte(sampleConfig))
	if err != nil {
		t.Fatal(err)
	}
	return cfg
}

func TestParseConfigRejectsInvalidNames(t *testing.T) {
	for _, data := range []string{`{"guests": {"-bad": {"type": "container"}}}`, `{"guests": {"ok": {}}}`, `{"guests": {"ok": {"type": "lxc"}}}`, `{"guests": null}`, `{}`, `[]`} {
		if _, err := parseConfig([]byte(data)); err == nil {
			t.Errorf("accepted %s", data)
		}
	}
	cfg := testConfig(t)
	if unit := cfg.Guests["worker"].CredentialUnit; unit == nil || *unit != "incus-guest-credentials-worker.service" {
		t.Errorf("credential unit %v", unit)
	}
	if file := cfg.Guests["worker"].CredentialFiles["/home/dev/.app/app.env"]; file.Owner != "dev" || file.Group != "users" || file.Mode != "0640" {
		t.Errorf("credential file %+v", file)
	}
}

func TestParseConfigRejectsInvalidCredentialFiles(t *testing.T) {
	for _, file := range []string{
		`"/run/secrets/x"`,
		`{"owner": "root", "group": "root", "mode": "0600"}`,
		`{"source": "/run/secrets/x", "owner": "Bad User", "group": "root", "mode": "0600"}`,
		`{"source": "/run/secrets/x", "owner": "root", "group": "r;m", "mode": "0600"}`,
		`{"source": "/run/secrets/x", "owner": "root", "group": "root", "mode": "600"}`,
		`{"source": "/run/secrets/x", "owner": "root", "group": "root", "mode": "0699"}`,
	} {
		data := `{"guests": {"ok": {"type": "container", "credentialFiles": {"/var/lib/ok/x": ` + file + `}}}}`
		if _, err := parseConfig([]byte(data)); err == nil {
			t.Errorf("accepted %s", file)
		}
	}
}

func TestParseCommand(t *testing.T) {
	cfg := testConfig(t)
	cmd, err := parseCommand([]string{"worker", "rebuild", "build", "--max-jobs", "1", "--cores", "2", "--override-input", "m", "path:/x"}, cfg)
	if err != nil {
		t.Fatal(err)
	}
	if cmd.action != "build" || *cmd.build.maxJobs != 1 || *cmd.build.cores != 2 || cmd.build.overrides[0] != [2]string{"m", "path:/x"} {
		t.Errorf("unexpected %+v", cmd)
	}
	cmd, err = parseCommand([]string{"worker", "rebuild", "--rollback"}, cfg)
	if err != nil || cmd.action != "switch" || !cmd.rollback {
		t.Errorf("default rebuild: %+v %v", cmd, err)
	}
	cmd, err = parseCommand([]string{"worker", "rebuild", "switch", "server-nix"}, cfg)
	if err != nil || cmd.action != "switch" || cmd.build.flake != "server-nix" {
		t.Errorf("rebuild FLAKE: %+v %v", cmd, err)
	}
	cmd, err = parseCommand([]string{"worker", "boot", "--flake", "path:/w"}, cfg)
	if err != nil || cmd.build.flake != "path:/w" {
		t.Errorf("boot --flake: %+v %v", cmd, err)
	}
	cmd, err = parseCommand([]string{"worker", "push-file", "dev", "/p/s.env", "app/s.env", "--user-unit", "app.service"}, cfg)
	if err != nil || cmd.user != "dev" || cmd.source != "/p/s.env" || cmd.destination != "app/s.env" || cmd.userUnit != "app.service" {
		t.Errorf("push-file: %+v %v", cmd, err)
	}
	for _, bad := range [][]string{
		{"other", "boot"},
		{"worker"},
		{"worker", "boot", "extra"},
		{"worker", "rebuild", "nope"},
		{"worker", "rebuild", "switch", "boot"},
		{"worker", "rebuild", "switch", "a", "b"},
		{"worker", "rebuild", "switch", "a", "--flake", "b"},
		{"worker", "boot", "--max-jobs", "-1"},
		{"worker", "boot", "--max-jobs"},
		{"worker", "stop", "--rollback"},
		{"worker", "passwd"},
		{"worker", "push-file", "dev", "src", "dst", "--system-unit", "a.service", "--user-unit", "b.service"},
		{"worker", "frobnicate"},
	} {
		if _, err := parseCommand(bad, cfg); err == nil {
			t.Errorf("accepted %v", bad)
		}
	}
}

func TestPreseedDecision(t *testing.T) {
	cases := []struct {
		list string
		code int
		ok   bool
	}{
		{`[]`, 0, true},
		{`[{"name":"default"}]`, 1, true},
		{`[{"name":"other"},{"name":"default"}]`, 1, true},
		{`[{"name":"other"}]`, 0, false},
		{`null`, 0, false},
		{`[{"name":1}]`, 0, false},
		{`[1]`, 0, false},
		{`{}`, 0, false},
	}
	for _, c := range cases {
		code, err := preseedDecision([]byte(c.list), "default")
		if (err == nil) != c.ok || (c.ok && code != c.code) {
			t.Errorf("%s: code %d err %v", c.list, code, err)
		}
	}
	if _, err := preseedCondition(nil); err == nil {
		t.Error("missing pool accepted")
	}
}

func TestFindInstance(t *testing.T) {
	list := []byte(`[{"name":"worker","type":"virtual-machine","status":"Running"},{"name":"box","type":"container","status":"Stopped"}]`)
	if found, err := findInstance(list, "worker", virtualMachine); err != nil || found["status"] != "Running" {
		t.Errorf("worker: %v %v", found, err)
	}
	if found, err := findInstance(list, "box", container); err != nil || found["status"] != "Stopped" {
		t.Errorf("box: %v %v", found, err)
	}
	if found, err := findInstance(list, "missing", container); err != nil || found != nil {
		t.Errorf("missing: %v %v", found, err)
	}
	if _, err := findInstance(list, "box", virtualMachine); err == nil {
		t.Error("container accepted as VM")
	}
	if _, err := findInstance(list, "worker", container); err == nil {
		t.Error("VM accepted as container")
	}
	if _, err := findInstance([]byte(`null`), "worker", virtualMachine); err == nil {
		t.Error("null list accepted")
	}
}

func TestDeviceValues(t *testing.T) {
	devices, err := testConfig(t).Guests["worker"].devices()
	if err != nil {
		t.Fatal(err)
	}
	got := deviceValues(devices["gpu"])
	want := []string{"pci=0000:01:00.0", "productid=1", "required=true"}
	if !slices.Equal(got, want) {
		t.Errorf("got %v want %v", got, want)
	}
}

func TestGuestShape(t *testing.T) {
	if !guestShape([]byte(`{"isContainer":false,"incusAgent":true}`), virtualMachine) {
		t.Error("valid VM shape rejected")
	}
	for _, good := range []string{`{"isContainer":true,"incusAgent":false}`, `{"isContainer":true,"incusAgent":true}`} {
		if !guestShape([]byte(good), container) {
			t.Errorf("valid container shape rejected: %s", good)
		}
	}
	for _, bad := range []string{`{"isContainer":true,"incusAgent":true}`, `{"isContainer":false,"incusAgent":false}`, `{"isContainer":false}`, `{"isContainer":false,"incusAgent":true,"x":1}`, `null`} {
		if guestShape([]byte(bad), virtualMachine) {
			t.Errorf("accepted VM %s", bad)
		}
	}
	for _, bad := range []string{`{"isContainer":false,"incusAgent":true}`, `{"isContainer":true}`, `null`} {
		if guestShape([]byte(bad), container) {
			t.Errorf("accepted container %s", bad)
		}
	}
}

func TestImageFile(t *testing.T) {
	root := t.TempDir()
	for _, file := range []string{"tarball/meta.tar.xz", "disk.qcow2", "rootfs.squashfs", "other/file.tar.xz"} {
		path := filepath.Join(root, file)
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(file), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	if got, err := imageFile(root, ""); err != nil || got != filepath.Join(root, "tarball/meta.tar.xz") {
		t.Errorf("metadata: %s %v", got, err)
	}
	for _, kind := range []string{virtualMachine, container} {
		output, extension := rootImage(kind)
		got, err := imageFile(root, extension)
		want := map[string]string{"qemuImage": "disk.qcow2", "squashfs": "rootfs.squashfs"}[output]
		if err != nil || got != filepath.Join(root, want) {
			t.Errorf("%s root image: %s %v", kind, got, err)
		}
	}
	if _, err := imageFile(t.TempDir(), ".qcow2"); err == nil {
		t.Error("empty directory accepted")
	}
	sum, err := fingerprint(filepath.Join(root, "tarball/meta.tar.xz"), filepath.Join(root, "disk.qcow2"))
	// sha256("tarball/meta.tar.xzdisk.qcow2")
	if err != nil || len(sum) != 64 {
		t.Errorf("fingerprint %s %v", sum, err)
	}
}

func TestBootstrapValidation(t *testing.T) {
	for _, good := range []string{"code-server/server.env", ".pi/agent/auth.json", "a"} {
		if !validDestination(good) {
			t.Errorf("rejected %s", good)
		}
	}
	for _, bad := range []string{"/etc/passwd", "../x", "a/../b", "a//b", "a/./b", "", "a/"} {
		if validDestination(bad) {
			t.Errorf("accepted %s", bad)
		}
	}
	if a, err := parseAccount("dev:x:1000:100::/home/dev:/run/current-system/sw/bin/bash\n", "dev"); err != nil || a.uid != 1000 || a.home != "/home/dev" {
		t.Errorf("account %+v %v", a, err)
	}
	for _, line := range []string{
		"root:x:0:0::/root:/bin/sh",
		"svc:x:1001:100::/var/empty:/run/current-system/sw/bin/nologin",
		"dev:x:1000:100::/:/bin/sh",
		"dev:x:1000:100::relative:/bin/sh",
		"other:x:1000:100::/home/other:/bin/sh",
	} {
		if _, err := parseAccount(line, "dev"); err == nil {
			t.Errorf("accepted %s", line)
		}
	}
	for _, user := range []string{"dev", "_svc", "a-b$"} {
		if !guestUser.MatchString(user) {
			t.Errorf("rejected user %s", user)
		}
	}
	for _, user := range []string{"Dev", "1a", "a b", "../x"} {
		if guestUser.MatchString(user) {
			t.Errorf("accepted user %s", user)
		}
	}
	if !serviceUnit.MatchString("paseo-daemon.service") || serviceUnit.MatchString("x.timer") {
		t.Error("service unit pattern")
	}
	if !storePath.MatchString("/nix/store/"+"0123456789abcdefghijklmnopqrstuv"+"-nixos-system-x") || storePath.MatchString("/nix/store/short-x") {
		t.Error("store path pattern")
	}
	var raw json.RawMessage = []byte(`{"a": [1, 2]}`)
	if string(compact(raw)) != `{"a":[1,2]}` {
		t.Error("compact")
	}
}
