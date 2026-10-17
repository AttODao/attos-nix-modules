package main

import (
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

func newCommand(args []string) error {
	if len(args) < 1 {
		return usageError("usage: atcoder-go new <contest-id> [acc options]")
	}
	root, err := projectRoot()
	if err != nil {
		return err
	}
	return command(root, "acc", append([]string{"new", args[0], "--choice", "all", "--template", "go"}, args[1:]...)...)
}

func requireTask(needTests bool) error {
	if !exists("main.go") {
		return errors.New("main.go was not found; run this from a task directory")
	}
	if needTests && !exists("tests") {
		return errors.New("tests directory was not found; create the task with 'atcoder-go new' first")
	}
	return nil
}

func testCommand(args []string) error {
	if err := requireTask(true); err != nil {
		return err
	}
	build, err := os.MkdirTemp("", "atcoder-test.")
	if err != nil {
		return err
	}
	defer os.RemoveAll(build)
	// The project library package is merged into the entry file, exactly as submitted.
	source := filepath.Join(build, "main.go")
	if err := snippet("main.go", "", source); err != nil {
		return err
	}
	binary := filepath.Join(build, "main")
	if err := goCommand("", "build", "-o", binary, source); err != nil {
		return err
	}
	return command("", "oj", append([]string{"test", "-c", binary, "-d", "tests", "--ignore-spaces-and-newlines"}, args...)...)
}

func submitCommand(args []string) error {
	if err := requireTask(false); err != nil {
		return err
	}
	if err := snippet("main.go", "", filepath.Join(".submit", "main.go")); err != nil {
		return err
	}
	language := os.Getenv("ATCODER_GO_LANGUAGE")
	if language == "" {
		language = "go " + atcoderGoVersion
	}
	// Keep oj's confirmation prompt; --no-open suits headless development containers.
	return command("", "acc", append([]string{"submit", ".submit/main.go", "--", "--no-open", "-l", language}, args...)...)
}

// loginCommand saves cookies at the tools' default paths and, inside devenv, shares the acc session with the project.
func loginCommand(args []string) error {
	home, err := os.UserHomeDir()
	if err != nil {
		return err
	}
	ojCookie := filepath.Join(home, ".local", "share", "online-judge-tools", "cookie.jar")
	accCookie := filepath.Join(home, ".config", "atcoder-cli-nodejs", "session.json")
	for _, dir := range []string{filepath.Dir(ojCookie), filepath.Dir(accCookie)} {
		if err := os.MkdirAll(dir, 0o700); err != nil {
			return err
		}
	}
	if err := command("", "aclogin", append([]string{"--tools", "oj", "acc", "--oj-cookie-path", ojCookie, "--acc-cookie-path", accCookie}, args...)...); err != nil {
		return err
	}
	if os.Getenv("DEVENV_ROOT") == "" {
		return nil
	}
	output, err := exec.Command("acc", "config-dir").Output()
	if err != nil {
		return err
	}
	configDir := strings.TrimSpace(string(output))
	if err := os.MkdirAll(configDir, 0o700); err != nil {
		return err
	}
	link := filepath.Join(configDir, "session.json")
	if err := os.Remove(link); err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	return os.Symlink(accCookie, link)
}
