package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const testKey = "dGVzdGtleXRlc3RrZXl0ZXN0a2V5dGVzdGtleXRlc3Q="

func writeKey(t *testing.T, dir, name string) string {
	path := filepath.Join(dir, name)
	if err := os.WriteFile(path, []byte(testKey+"\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestCheckClients(t *testing.T) {
	v6, mapped, upper := "fd00::2", "::ffff:10.0.0.9", "FD00::3"
	cases := map[string][]client{
		"bad name":       {{Name: "Bad", Address: "10.0.0.2"}},
		"duplicate name": {{Name: "a", Address: "10.0.0.2"}, {Name: "a", Address: "10.0.0.3"}},
		"leading zero":   {{Name: "a", Address: "10.0.0.02"}},
		"ipv6":           {{Name: "a", Address: "fd00::2"}},
		"duplicate addr": {{Name: "a", Address: "10.0.0.2"}, {Name: "b", Address: "10.0.0.2"}},
		"ipv4 as ipv6":   {{Name: "a", Address: "10.0.0.2", IPv6Address: &mapped}},
		"non-canonical":  {{Name: "a", Address: "10.0.0.2", IPv6Address: &upper}},
		"duplicate ipv6": {{Name: "a", Address: "10.0.0.2", IPv6Address: &v6}, {Name: "b", Address: "10.0.0.3", IPv6Address: &v6}},
	}
	for label, entries := range cases {
		if checkClients(entries) == nil {
			t.Errorf("%s: expected error", label)
		}
	}
	if err := checkClients([]client{{Name: "a_1-b", Address: "10.0.0.2", IPv6Address: &v6}}); err != nil {
		t.Fatal(err)
	}
}

func TestCheckEndpoint(t *testing.T) {
	for _, valid := range []string{"vpn.example.org:51820", "[fd00::1]:1", "a:65535"} {
		if _, err := checkEndpoint(valid); err != nil {
			t.Errorf("%s: %v", valid, err)
		}
	}
	for _, invalid := range []string{"vpn.example.org", "vpn:0", "vpn:65536", "vpn:+1", ":1", "a:b:1", "[nope]:1", "-a:1"} {
		if _, err := checkEndpoint(invalid); err == nil {
			t.Errorf("%s: expected error", invalid)
		}
	}
}

func TestKeyFile(t *testing.T) {
	dir := t.TempDir()
	if value, err := keyFile(writeKey(t, dir, "ok")); err != nil || value != testKey {
		t.Fatalf("%q %v", value, err)
	}
	short := filepath.Join(dir, "short")
	os.WriteFile(short, []byte("dGVzdA=="), 0o600)
	if _, err := keyFile(short); err == nil {
		t.Fatal("short key accepted")
	}
}

func TestSyncConfigs(t *testing.T) {
	dir := t.TempDir()
	root := filepath.Join(dir, "configs")
	psk := writeKey(t, dir, "psk")
	bobV6 := "fd00::3"
	meta := metadata{
		Clients: []client{
			{Name: "alice", Address: "10.252.0.2", PrivateKeyFile: writeKey(t, dir, "alice"), PresharedKeyFile: &psk},
			{Name: "bob", Address: "10.252.0.3", IPv6Address: &bobV6, PrivateKeyFile: writeKey(t, dir, "bob")},
		},
		ClientDNS:              "10.252.0.1",
		ClientEndpoint:         "wg.example.org:51820",
		ServerPublicKeyFile:    writeKey(t, dir, "server"),
		ClientConfigsDirectory: root,
		ClientConfigMode:       "0640",
	}
	os.MkdirAll(root, 0o700)
	os.WriteFile(filepath.Join(root, "old.conf"), nil, 0o600)
	os.WriteFile(filepath.Join(root, ".hidden.conf"), nil, 0o600)
	if err := syncConfigs(meta); err != nil {
		t.Fatal(err)
	}
	alice, _ := os.ReadFile(filepath.Join(root, "alice.conf"))
	want := "[Interface]\nPrivateKey = " + testKey + "\nAddress = 10.252.0.2/32\nDNS = 10.252.0.1\n\n[Peer]\nPublicKey = " + testKey +
		"\nPresharedKey = " + testKey + "\nAllowedIPs = 0.0.0.0/0\nEndpoint = wg.example.org:51820\nPersistentKeepalive = 25\n"
	if string(alice) != want {
		t.Fatalf("unexpected config:\n%s", alice)
	}
	bob, _ := os.ReadFile(filepath.Join(root, "bob.conf"))
	if strings.Contains(string(bob), "PresharedKey") {
		t.Fatal("unexpected preshared key")
	}
	if !strings.Contains(string(bob), "\nAddress = 10.252.0.3/32, fd00::3/128\n") ||
		!strings.Contains(string(bob), "\nAllowedIPs = 0.0.0.0/0, ::/0\n") {
		t.Fatalf("missing IPv6 in config:\n%s", bob)
	}
	if info, _ := os.Stat(filepath.Join(root, "bob.conf")); info.Mode().Perm() != 0o640 {
		t.Fatalf("mode %v", info.Mode())
	}
	if _, err := os.Stat(filepath.Join(root, "old.conf")); !os.IsNotExist(err) {
		t.Fatal("stale config kept")
	}
	if _, err := os.Stat(filepath.Join(root, ".hidden.conf")); err != nil {
		t.Fatal("hidden file removed")
	}
	meta.ClientConfigMode = "0644"
	if syncConfigs(meta) == nil {
		t.Fatal("invalid mode accepted")
	}
}
