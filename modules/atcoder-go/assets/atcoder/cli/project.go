package main

import (
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"slices"
	"strings"
)

const atcoderGoVersion = "1.25.1"

var libraries = []string{
	"github.com/emirpasic/gods",
	"gonum.org/v1/gonum",
	"github.com/liyue201/gostl",
	"github.com/benbjohnson/immutable",
	"golang.org/x/exp",
	"github.com/monkukui/ac-library-go",
}

// goTool prefers the toolchain selected by the Home Manager module over PATH.
func goTool() string {
	if dir := os.Getenv("ATCODER_GO_BIN_DIR"); dir != "" {
		return filepath.Join(dir, "go")
	}
	return "go"
}

func goCommand(dir string, args ...string) error {
	os.Setenv("GOTOOLCHAIN", "local")
	return command(dir, goTool(), args...)
}

func findProjectRoot(start string) (string, error) {
	for current := start; ; current = filepath.Dir(current) {
		if _, err := os.Stat(filepath.Join(current, "go.mod")); err == nil {
			return current, nil
		}
		if filepath.Dir(current) == current {
			return "", errors.New("go.mod was not found; run 'atcoder-go init' at the project root")
		}
	}
}

func projectRoot() (string, error) {
	if root := os.Getenv("ATCODER_GO_ROOT"); root != "" {
		return root, nil
	}
	cwd, err := os.Getwd()
	if err != nil {
		return "", err
	}
	return findProjectRoot(cwd)
}

// scaffolded projects pin the AtCoder Go version and bundled libraries; others only use go.mod as recorded.
func scaffolded(root string) bool {
	if os.Getenv("ATCODER_PROJECT_ASSETS") != "" {
		return true
	}
	info, err := os.Stat(filepath.Join(root, ".atcoder"))
	return err == nil && info.IsDir()
}

func initCommand(args []string) error {
	if len(args) != 0 {
		return usageError("usage: atcoder-go init")
	}
	root, err := os.Getwd()
	if err != nil {
		return err
	}
	if assets := os.Getenv("ATCODER_PROJECT_ASSETS"); assets != "" {
		if err := scaffold(assets, root); err != nil {
			return err
		}
	}
	if _, err := os.Stat(filepath.Join(root, "go.mod")); errors.Is(err, fs.ErrNotExist) {
		module := os.Getenv("ATCODER_GO_MODULE")
		if module == "" {
			module = "atcoder.jp/golang"
		}
		if err := goCommand(root, "mod", "init", module); err != nil {
			return err
		}
	}
	if scaffolded(root) {
		if err := addLibraries(root); err != nil {
			return err
		}
	} else {
		for _, entry := range []string{".direnv/", ".devenv/"} {
			if err := ensureLine(filepath.Join(root, ".gitignore"), entry); err != nil {
				return err
			}
		}
		if exists(filepath.Join(root, "devenv.nix")) && !exists(filepath.Join(root, ".envrc")) {
			if err := os.WriteFile(filepath.Join(root, ".envrc"), []byte("use devenv\n"), 0o644); err != nil {
				return err
			}
		}
	}
	fmt.Println("initialized AtCoder Go project:", root)
	if scaffolded(root) {
		fmt.Println("run 'direnv allow' here to activate devenv")
	}
	return nil
}

func syncCommand(args []string) error {
	if len(args) != 0 {
		return usageError("usage: atcoder-go sync")
	}
	root, err := projectRoot()
	if err != nil {
		return err
	}
	if scaffolded(root) {
		return addLibraries(root)
	}
	// Download recorded dependencies without upgrading modules or the toolchain.
	return goCommand(root, "mod", "download")
}

func versionCommand(args []string) error {
	if len(args) != 0 {
		return usageError("usage: atcoder-go version")
	}
	return goCommand("", "version")
}

func addLibraries(root string) error {
	if err := os.MkdirAll(filepath.Join(root, "library"), 0o755); err != nil {
		return err
	}
	pin := "-go=" + atcoderGoVersion
	if err := goCommand(root, "mod", "edit", pin); err != nil {
		return err
	}
	if err := goCommand(root, append([]string{"get"}, libraries...)...); err != nil {
		return err
	}
	// go get may raise the go directive; restore the judge version.
	return goCommand(root, "mod", "edit", pin)
}

// scaffold copies project assets without overwriting files the user already has.
func scaffold(assets, root string) error {
	if err := copyMissing(filepath.Join(assets, ".atcoder"), filepath.Join(root, ".atcoder")); err != nil {
		return err
	}
	for _, name := range []string{"devenv.nix", "devenv.yaml", ".gitignore"} {
		if err := copyMissing(filepath.Join(assets, name), filepath.Join(root, name)); err != nil {
			return err
		}
	}
	envrc := filepath.Join(root, ".envrc")
	legacy, _ := os.ReadFile(envrc)
	if strings.Contains(string(legacy), "source_env .atcoder-go.env") {
		// Replace the retired env-file indirection with the bundled .envrc.
		if err := os.Remove(envrc); err != nil {
			return err
		}
		if err := os.Remove(filepath.Join(root, ".atcoder-go.env")); err != nil && !errors.Is(err, fs.ErrNotExist) {
			return err
		}
	}
	if err := copyMissing(filepath.Join(assets, ".envrc"), envrc); err != nil {
		return err
	}
	for _, entry := range []string{".devenv/", ".direnv/", ".submit/", ".atcoder-go.env"} {
		if err := ensureLine(filepath.Join(root, ".gitignore"), entry); err != nil {
			return err
		}
	}
	return nil
}

// copyMissing copies a file or tree from the read-only store, making copies user-writable.
func copyMissing(source, target string) error {
	return filepath.WalkDir(source, func(path string, entry fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		relative, err := filepath.Rel(source, path)
		if err != nil {
			return err
		}
		destination := filepath.Join(target, relative)
		info, err := entry.Info()
		if err != nil {
			return err
		}
		if entry.IsDir() {
			if err := os.MkdirAll(destination, 0o755); err != nil {
				return err
			}
			return os.Chmod(destination, info.Mode().Perm()|0o700)
		}
		if exists(destination) {
			return nil
		}
		return copyFile(path, destination, info.Mode().Perm()|0o600)
	})
}

func copyFile(source, destination string, mode fs.FileMode) error {
	in, err := os.Open(source)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.OpenFile(destination, os.O_WRONLY|os.O_CREATE|os.O_EXCL, mode)
	if err != nil {
		return err
	}
	if _, err := io.Copy(out, in); err != nil {
		out.Close()
		return err
	}
	return out.Close()
}

func ensureLine(path, line string) error {
	content, err := os.ReadFile(path)
	if err != nil && !errors.Is(err, fs.ErrNotExist) {
		return err
	}
	if slices.Contains(strings.Split(string(content), "\n"), line) {
		return nil
	}
	if len(content) > 0 && !strings.HasSuffix(string(content), "\n") {
		line = "\n" + line
	}
	file, err := os.OpenFile(path, os.O_WRONLY|os.O_APPEND|os.O_CREATE, 0o644)
	if err != nil {
		return err
	}
	if _, err := file.WriteString(line + "\n"); err != nil {
		file.Close()
		return err
	}
	return file.Close()
}

func exists(path string) bool {
	_, err := os.Lstat(path)
	return err == nil
}
