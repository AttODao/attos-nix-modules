package main

import (
	"encoding/json"
	"os"
	"path/filepath"
	"slices"
	"testing"
)

const sampleConfig = `{
  "flakeFile": "/srv/flake.nix",
  "virtualMachines": {
    "worker": {
      "launchConfig": {"devices": {"gpu": {"type": "gpu", "pci": "0000:01:00.0", "productid": 1, "required": true}}},
      "managedDeviceNames": ["gpu"],
      "credentialUnit": "incus-vm-credentials-worker.service",
      "credentialFiles": {"/var/lib/worker/token.env": "/run/secrets/worker.env"},
      "credentialRestartUnits": ["worker.service"]
    }
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
	for _, data := range []string{`{"virtualMachines": {"-bad": {}}}`, `{"virtualMachines": null}`, `{}`, `[]`} {
		if _, err := parseConfig([]byte(data)); err == nil {
			t.Errorf("accepted %s", data)
		}
	}
	cfg := testConfig(t)
	if unit := cfg.VirtualMachines["worker"].CredentialUnit; unit == nil || *unit != "incus-vm-credentials-worker.service" {
		t.Errorf("credential unit %v", unit)
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
	list := []byte(`[{"name":"worker","type":"virtual-machine","status":"Running"},{"name":"box","type":"container"}]`)
	if found, err := findInstance(list, "worker"); err != nil || found["status"] != "Running" {
		t.Errorf("worker: %v %v", found, err)
	}
	if found, err := findInstance(list, "missing"); err != nil || found != nil {
		t.Errorf("missing: %v %v", found, err)
	}
	if _, err := findInstance(list, "box"); err == nil {
		t.Error("container accepted as VM")
	}
	if _, err := findInstance([]byte(`null`), "worker"); err == nil {
		t.Error("null list accepted")
	}
}

func TestDeviceValues(t *testing.T) {
	devices, err := testConfig(t).VirtualMachines["worker"].devices()
	if err != nil {
		t.Fatal(err)
	}
	got := deviceValues(devices["gpu"])
	want := []string{"pci=0000:01:00.0", "productid=1", "required=true"}
	if !slices.Equal(got, want) {
		t.Errorf("got %v want %v", got, want)
	}
}

func TestVMGuestShape(t *testing.T) {
	if !vmGuestShape([]byte(`{"isContainer":false,"incusAgent":true}`)) {
		t.Error("valid shape rejected")
	}
	for _, bad := range []string{`{"isContainer":true,"incusAgent":true}`, `{"isContainer":false}`, `{"isContainer":false,"incusAgent":true,"x":1}`, `null`} {
		if vmGuestShape([]byte(bad)) {
			t.Errorf("accepted %s", bad)
		}
	}
}

func TestImageFile(t *testing.T) {
	root := t.TempDir()
	for _, file := range []string{"tarball/meta.tar.xz", "disk.qcow2", "other/file.tar.xz"} {
		path := filepath.Join(root, file)
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(file), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	if got, err := imageFile(root, true); err != nil || got != filepath.Join(root, "tarball/meta.tar.xz") {
		t.Errorf("metadata: %s %v", got, err)
	}
	if got, err := imageFile(root, false); err != nil || got != filepath.Join(root, "disk.qcow2") {
		t.Errorf("disk: %s %v", got, err)
	}
	if _, err := imageFile(t.TempDir(), false); err == nil {
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
