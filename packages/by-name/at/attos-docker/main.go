// attos-docker ensures shared Docker bridge networks. Docker is invoked through its CLI.
package main

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"strings"
)

const usage = `usage:
  attos-docker network ensure --docker PATH --name NAME [--subnet CIDR [--gateway IP]] [--opt KEY=VALUE]...`

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, "attos-docker:", err)
		os.Exit(1)
	}
}

func run(args []string) error {
	if len(args) < 2 {
		return errors.New(usage)
	}
	commands := map[string]func([]string) error{
		"network ensure": networkEnsure,
	}
	command, ok := commands[args[0]+" "+args[1]]
	if !ok {
		return errors.New(usage)
	}
	return command(args[2:])
}

type dockerCLI string

// output returns trimmed stdout and discards stderr (for expected probe failures).
func (d dockerCLI) output(args ...string) (string, error) {
	out, err := exec.Command(string(d), args...).Output()
	if err != nil {
		return "", fmt.Errorf("docker %s failed", strings.Join(args[:min(2, len(args))], " "))
	}
	return strings.TrimSpace(string(out)), nil
}
