package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

func TestCombineLibrary(t *testing.T) {
	root := t.TempDir()
	t.Setenv("ATCODER_GO_ROOT", root)
	library := filepath.Join(root, "library")
	if err := os.Mkdir(library, 0755); err != nil {
		t.Fatal(err)
	}
	entry := filepath.Join(root, "main.go")
	for path, source := range map[string]string{
		entry: `package main
import ("fmt"; "atcoder.jp/golang/library")
func main() { fmt.Println(library.Answer()) }
`,
		filepath.Join(library, "answer.go"): "package library\nfunc Answer() int { return 42 }\n",
	} {
		if err := os.WriteFile(path, []byte(source), 0600); err != nil {
			t.Fatal(err)
		}
	}
	output := filepath.Join(root, ".submit", "main.go")
	if err := run(entry, "", output); err != nil {
		t.Fatal(err)
	}
	combined, err := os.ReadFile(output)
	if err != nil || strings.Contains(string(combined), "library.") || strings.Contains(string(combined), libraryImportPath) {
		t.Fatalf("library was not merged: %s (%v)", combined, err)
	}
	result, err := exec.Command("go", "run", output).CombinedOutput()
	if err != nil || string(result) != "42\n" {
		t.Fatalf("combined program failed: %s (%v)", result, err)
	}
}
