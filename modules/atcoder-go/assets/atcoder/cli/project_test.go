package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestFindProjectRoot(t *testing.T) {
	root := t.TempDir()
	nested := filepath.Join(root, "abc001", "a")
	if err := os.MkdirAll(nested, 0o755); err != nil {
		t.Fatal(err)
	}
	if _, err := findProjectRoot(nested); err == nil {
		t.Fatal("expected an error without go.mod")
	}
	if err := os.WriteFile(filepath.Join(root, "go.mod"), []byte("module x\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if found, err := findProjectRoot(nested); err != nil || found != root {
		t.Fatalf("found %q (%v), want %q", found, err, root)
	}
}

func TestScaffoldKeepsUserFiles(t *testing.T) {
	assets, root := t.TempDir(), t.TempDir()
	for path, content := range map[string]string{
		".atcoder/template/main.go": "template\n",
		"devenv.nix":                "{}\n",
		"devenv.yaml":               "inputs: {}\n",
		".gitignore":                ".devenv/\n",
		".envrc":                    "use devenv\n",
	} {
		full := filepath.Join(assets, path)
		if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(full, []byte(content), 0o444); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.WriteFile(filepath.Join(root, "devenv.nix"), []byte("mine\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, ".envrc"), []byte("source_env .atcoder-go.env\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := scaffold(assets, root); err != nil {
		t.Fatal(err)
	}
	if content, _ := os.ReadFile(filepath.Join(root, "devenv.nix")); string(content) != "mine\n" {
		t.Fatalf("user devenv.nix overwritten: %q", content)
	}
	if content, _ := os.ReadFile(filepath.Join(root, ".envrc")); string(content) != "use devenv\n" {
		t.Fatalf("legacy .envrc not replaced: %q", content)
	}
	info, err := os.Stat(filepath.Join(root, ".atcoder/template/main.go"))
	if err != nil || info.Mode().Perm()&0o200 == 0 {
		t.Fatalf("copied asset is not user-writable: %v %v", info, err)
	}
	gitignore, _ := os.ReadFile(filepath.Join(root, ".gitignore"))
	for _, entry := range []string{".devenv/", ".direnv/", ".submit/", ".atcoder-go.env"} {
		if strings.Count(string(gitignore), entry+"\n") != 1 {
			t.Fatalf(".gitignore entry %q missing or duplicated: %q", entry, gitignore)
		}
	}
}
