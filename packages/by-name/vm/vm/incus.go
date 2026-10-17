package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strconv"
	"strings"
)

var incusBase = []string{"incus", "--force-local"}

// commandError is a failed external command; its output is never interpreted.
type commandError struct {
	argv []string
	err  error
}

func (e *commandError) Error() string {
	shown := e.argv
	if len(shown) > 6 {
		shown = append(shown[:6:6], "...")
	}
	return fmt.Sprintf("command %q failed: %v", strings.Join(shown, " "), e.err)
}

func (e *commandError) Unwrap() error { return e.err }

// run executes argv with inherited stderr. stdin is inherited unless input is
// given; stdout is returned trimmed when capture is set, otherwise inherited.
func run(argv []string, capture bool, input io.Reader) (string, error) {
	c := exec.Command(argv[0], argv[1:]...)
	c.Stderr = os.Stderr
	c.Stdin = os.Stdin
	if input != nil {
		c.Stdin = input
	}
	var out bytes.Buffer
	c.Stdout = os.Stdout
	if capture {
		c.Stdout = &out
	}
	if err := c.Run(); err != nil {
		return "", &commandError{argv, err}
	}
	return strings.TrimSpace(out.String()), nil
}

func incusArgv(arguments ...string) []string {
	return append(append(append([]string{}, incusBase...), "--project", "default"), arguments...)
}

func incus(capture bool, input io.Reader, arguments ...string) (string, error) {
	return run(incusArgv(arguments...), capture, input)
}

type identity struct{ uid, gid int }

// guest builds an incus exec argv with an explicit NixOS PATH.
func guest(name string, command []string, as *identity, interactive bool) []string {
	argv := incusArgv("exec", name)
	if as != nil {
		argv = append(argv, "--user", strconv.Itoa(as.uid), "--group", strconv.Itoa(as.gid))
	}
	mode := "non-interactive"
	if interactive {
		mode = "interactive"
	}
	argv = append(argv, "--env=PATH=/run/current-system/sw/bin:/bin", "--mode="+mode, "--")
	return append(argv, command...)
}

func requireRunning(name string) error {
	out, err := run(append(append([]string{}, incusBase...), "query", "/1.0/instances/"+name+"?project=default"), true, nil)
	if err != nil {
		return err
	}
	var instance map[string]any
	if err := json.Unmarshal([]byte(out), &instance); err != nil {
		return fmt.Errorf("unexpected Incus instance: %w", err)
	}
	if instance["type"] != "virtual-machine" || instance["status"] != "Running" {
		return errors.New("Target must be an existing Running virtual-machine; start it with: vm " + name + " boot")
	}
	return nil
}

// instance returns the named instance, or nil; a container is never treated as the VM.
func instance(name string) (map[string]any, error) {
	out, err := incus(true, nil, "list", "--format=json")
	if err != nil {
		return nil, err
	}
	return findInstance([]byte(out), name)
}

func findInstance(list []byte, name string) (map[string]any, error) {
	current, ok := objectList(list)
	if !ok {
		return nil, errors.New("Unexpected Incus instance list")
	}
	for _, item := range current {
		if item["name"] == name {
			if item["type"] != "virtual-machine" {
				return nil, errors.New("Incus instance " + name + " is not a virtual-machine; it is never converted or deleted")
			}
			return item, nil
		}
	}
	return nil, nil
}
