// attos-docker ensures shared Docker bridge networks and runs the Docker Swarm
// operations of the swarm module. Docker is invoked through its CLI; no secret is
// ever written to standard output or the journal.
package main

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"strings"
)

const usage = `usage:
  attos-docker network ensure --docker PATH --name NAME [--subnet CIDR [--gateway IP]] [--opt KEY=VALUE]...
  attos-docker swarm manager --docker PATH ADVERTISE_ADDRESS TOKEN_FILE
  attos-docker swarm worker --docker PATH MANAGER_ADDRESS TOKEN_FILE
  attos-docker swarm network --docker PATH MARKER_DIR [NETWORK]...
  attos-docker swarm fetch [--source ADDRESS] URL TOKEN_FILE
  attos-docker swarm wait --docker PATH URL [NETWORK]
  attos-docker swarm serve --address IP --port PORT --marker MARKER_DIR [--token TOKEN_FILE]`

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
		"swarm manager":  swarmManager,
		"swarm worker":   swarmWorker,
		"swarm network":  swarmNetwork,
		"swarm fetch":    swarmFetch,
		"swarm wait":     swarmWait,
		"swarm serve":    swarmServe,
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

// run discards stdout, which may contain join tokens, and keeps stderr for diagnosis.
func (d dockerCLI) run(args ...string) error {
	cmd := exec.Command(string(d), args...)
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("docker %s failed", strings.Join(args[:min(2, len(args))], " "))
	}
	return nil
}

// writeSecret atomically replaces path with a 0600 file containing data.
func writeSecret(path string, data []byte) error {
	dir := path[:strings.LastIndex(path, "/")+1]
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	tmp, err := os.CreateTemp(dir, ".token-*")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name())
	if err := tmp.Chmod(0o600); err != nil {
		tmp.Close()
		return err
	}
	if _, err := tmp.Write(data); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	return os.Rename(tmp.Name(), path)
}
