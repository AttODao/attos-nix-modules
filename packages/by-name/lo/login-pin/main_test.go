package main

import (
	"bufio"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestValidPIN(t *testing.T) {
	for _, pin := range []string{"000000", "123456"} {
		if !validPIN(pin) {
			t.Errorf("%q rejected", pin)
		}
	}
	for _, pin := range []string{"", "12345", "1234567", "12345a", "１２３４５６", "123 456"} {
		if validPIN(pin) {
			t.Errorf("%q accepted", pin)
		}
	}
}

func TestReadLine(t *testing.T) {
	reader := bufio.NewReader(strings.NewReader(" 123456 \n\\12\nlast"))
	for _, want := range []string{"123456", "\\12", "last"} {
		if got, err := readLine(reader); err != nil || got != want {
			t.Fatalf("got %q %v want %q", got, err, want)
		}
	}
	if _, err := readLine(reader); err == nil {
		t.Fatal("EOF accepted")
	}
}

func TestDatabaseFormat(t *testing.T) {
	if dbLoadInput("attodao", "$y$hash") != "attodao\n$y$hash\n" {
		t.Fatal("unexpected db_load input")
	}
	for _, tool := range []string{"mkpasswd", "db_load", "db_dump"} {
		if _, err := exec.LookPath(tool); err != nil {
			t.Skip(tool + " unavailable")
		}
	}
	hash, err := hashPIN("123456")
	if err != nil {
		t.Fatal(err)
	}
	dir := filepath.Join(t.TempDir(), "login-pin")
	if err := store(dir, "attodao", hash); err != nil {
		t.Fatal(err)
	}
	info, err := os.Stat(filepath.Join(dir, "pins.db"))
	if err != nil || info.Mode().Perm() != 0o600 {
		t.Fatalf("database mode: %v %v", info, err)
	}
	if entries, _ := os.ReadDir(dir); len(entries) != 1 {
		t.Fatalf("temporary files left: %v", entries)
	}
	dump, err := exec.Command("db_dump", "-p", filepath.Join(dir, "pins.db")).Output()
	if err != nil || !strings.Contains(string(dump), " attodao\n "+hash+"\n") {
		t.Fatalf("unexpected database contents:\n%s", dump)
	}
}
