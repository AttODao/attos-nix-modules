// atcoder-go manages AtCoder Go projects: scaffolding, dependencies, contests, local tests and submissions.
package main

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
)

const usage = `usage: atcoder-go <command> [args]

commands:
  init                 scaffold and initialize the project in the current directory (default)
  sync                 restore the project's Go dependencies
  version              print the Go toolchain version
  new <contest> [...]  create a contest with acc
  test [...]           build the current task and run oj test
  submit [...]         merge the library and submit the current task with acc
  snippet [flags]      merge main.go and the project library into one file
  login [...]          save AtCoder cookies for oj and acc with aclogin`

type usageError string

func (e usageError) Error() string { return string(e) }

func main() {
	command, args := "init", []string(nil)
	if len(os.Args) > 1 {
		command, args = os.Args[1], os.Args[2:]
	}
	commands := map[string]func([]string) error{
		"init":    initCommand,
		"sync":    syncCommand,
		"version": versionCommand,
		"new":     newCommand,
		"test":    testCommand,
		"submit":  submitCommand,
		"snippet": snippetCommand,
		"login":   loginCommand,
	}
	run, ok := commands[command]
	if !ok {
		fmt.Fprintln(os.Stderr, usage)
		os.Exit(2)
	}
	err := run(args)
	var exitErr *exec.ExitError
	var usageErr usageError
	switch {
	case err == nil:
	case errors.As(err, &exitErr):
		os.Exit(exitErr.ExitCode())
	case errors.As(err, &usageErr):
		fmt.Fprintln(os.Stderr, usageErr)
		os.Exit(2)
	default:
		fmt.Fprintln(os.Stderr, "atcoder-go:", err)
		os.Exit(1)
	}
}

// command runs an external tool attached to the terminal in dir.
func command(dir, name string, args ...string) error {
	cmd := exec.Command(name, args...)
	cmd.Dir = dir
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
	return cmd.Run()
}
