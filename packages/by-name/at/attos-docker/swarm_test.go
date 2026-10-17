package main

import (
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
)

func TestEncryptedOverlay(t *testing.T) {
	for metadata, want := range map[string]bool{
		"overlay true swarm encrypted ":             true,
		"overlay true swarm com.docker.x encrypted": true,
		"overlay true swarm ":                       false,
		"overlay false swarm encrypted ":            false,
		"bridge true local encrypted ":              false,
		"":                                          false,
	} {
		if got := encryptedOverlay(metadata); got != want {
			t.Errorf("%q: got %v want %v", metadata, got, want)
		}
	}
}

func TestValidToken(t *testing.T) {
	if !validToken([]byte("SWMTKN-1-abc\r\n")) || validToken([]byte("<html>")) || validToken(nil) {
		t.Fatal("token validation")
	}
}

func TestValidBackend(t *testing.T) {
	for name, want := range map[string]bool{"backend-forgejo": true, "backend-": false, "backend-A": false, "../ready": false, "ready": false} {
		if validBackend(name) != want {
			t.Errorf("%q", name)
		}
	}
}

func TestReadinessHandler(t *testing.T) {
	marker := t.TempDir()
	tokenFile := filepath.Join(t.TempDir(), "worker-token")
	status := func(h http.Handler, path string) (int, string) {
		w := httptest.NewRecorder()
		h.ServeHTTP(w, httptest.NewRequest(http.MethodGet, path, nil))
		return w.Code, w.Body.String()
	}
	readiness := readinessHandler(marker, "")
	transport := readinessHandler(marker, tokenFile)
	if code, _ := status(readiness, "/networks-ready"); code != http.StatusServiceUnavailable {
		t.Fatalf("not ready: %d", code)
	}
	for _, name := range []string{"ready", "backend-a"} {
		if err := os.WriteFile(filepath.Join(marker, name), nil, 0o644); err != nil {
			t.Fatal(err)
		}
	}
	checks := []struct {
		h    http.Handler
		path string
		code int
	}{
		{readiness, "/networks-ready", 200},
		{readiness, "/networks-ready/backend-a", 200},
		{readiness, "/networks-ready/backend-b", 503},
		{readiness, "/networks-ready/../ready", 404},
		{readiness, "/worker-token", 404},
		{transport, "/worker-token", 503},
		{transport, "/other", 404},
	}
	for _, c := range checks {
		if code, _ := status(c.h, c.path); code != c.code {
			t.Errorf("%s: got %d want %d", c.path, code, c.code)
		}
	}
	if err := os.WriteFile(tokenFile, []byte("SWMTKN-1-x\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if code, body := status(transport, "/worker-token"); code != 200 || body != "SWMTKN-1-x\n" {
		t.Errorf("token: %d %q", code, body)
	}
}

func TestWriteSecret(t *testing.T) {
	path := filepath.Join(t.TempDir(), "sub", "token")
	if err := writeSecret(path, []byte("x")); err != nil {
		t.Fatal(err)
	}
	info, err := os.Stat(path)
	if err != nil || info.Mode().Perm() != 0o600 {
		t.Fatalf("mode %v %v", info.Mode(), err)
	}
	if matches, _ := filepath.Glob(filepath.Join(filepath.Dir(path), ".token-*")); len(matches) != 0 {
		t.Fatalf("leftover temp files %v", matches)
	}
}
