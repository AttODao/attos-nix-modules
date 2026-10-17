package main

import (
	"os"
	"path/filepath"
	"slices"
	"testing"
)

func writeFile(t *testing.T, path, content string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestPrefixIsCurrent(t *testing.T) {
	prefix := t.TempDir()
	driver := filepath.Join(t.TempDir(), "pipeasio64.dll")
	writeFile(t, driver, "driver")
	writeFile(t, filepath.Join(prefix, "drive_c/windows/system32/pipeasio64.dll"), "driver")
	writeFile(t, filepath.Join(prefix, "system.reg"), "[Software\\\\ASIO\\\\PipeASIO] 1700000000\n\"CLSID\"=\""+registryCLSID+"\"\n\"Description\"=\"PipeASIO\"\n\n[Other]\n")
	if !prefixIsCurrent(prefix, driver) {
		t.Fatal("registered prefix not detected")
	}
	writeFile(t, filepath.Join(prefix, "drive_c/windows/system32/pipeasio64.dll"), "old")
	if prefixIsCurrent(prefix, driver) {
		t.Fatal("stale driver accepted")
	}
	writeFile(t, filepath.Join(prefix, "system.reg"), "[Other]\n\"CLSID\"=\""+registryCLSID+"\"\n")
	if prefixIsCurrent(prefix, driver) {
		t.Fatal("CLSID outside the PipeASIO key accepted")
	}
}

func TestSteamPrefixes(t *testing.T) {
	root := t.TempDir()
	launched := filepath.Join(root, "compatdata/10/pfx")
	if err := os.MkdirAll(launched, 0o755); err != nil {
		t.Fatal(err)
	}
	prefixes, targets := steamPrefixes([]target{
		{Kind: "steam", Prefix: launched, Runner: "first"},
		{Kind: "steam", Prefix: launched + "/.", Runner: "duplicate"},
		{Kind: "steam", Prefix: filepath.Join(root, "compatdata/20/pfx")},
		{Kind: "steam"},
		{Kind: "wine", Prefix: root},
	})
	if want := []string{canonical(launched)}; !slices.Equal(prefixes, want) || targets[want[0]].Runner != "first" {
		t.Fatalf("got %v %v", prefixes, targets)
	}
}

func TestRegistrationEnvironment(t *testing.T) {
	environment := registrationEnvironment([]string{"HOME=/h", "PROTON_LOG=1", "STEAM_COMPAT_APP_ID=1", "UMU_ID=2", "WINEDLLOVERRIDES=x", "PATH=/bin"}, "/c/10/pfx", "/proton", "/run")
	for _, unwanted := range []string{"PROTON_LOG=1", "STEAM_COMPAT_APP_ID=1", "UMU_ID=2", "WINEDLLOVERRIDES=x"} {
		if slices.Contains(environment, unwanted) {
			t.Fatalf("%s inherited: %v", unwanted, environment)
		}
	}
	for _, wanted := range []string{"HOME=/h", "PATH=/bin", "WINEPREFIX=/c/10/pfx", "STEAM_COMPAT_DATA_PATH=/c/10", "PROTONPATH=/proton", "WINE=/run"} {
		if !slices.Contains(environment, wanted) {
			t.Fatalf("%s missing: %v", wanted, environment)
		}
	}
}
