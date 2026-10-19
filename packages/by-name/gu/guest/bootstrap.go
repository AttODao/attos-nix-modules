package main

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path"
	"regexp"
	"strconv"
	"strings"
	"syscall"
)

// Explicit initial login/credential setup; never replace existing authentication.

var (
	guestUser   = regexp.MustCompile(`^[a-z_][a-z0-9_-]*\$?$`)
	serviceUnit = regexp.MustCompile(`^[A-Za-z0-9_.@:-]+\.service$`)
)

const installScript = `
set -eu
umask 077
home=$1
destination=$2
case "$(realpath -m -- "$destination")" in "$home"/*) ;; *) exit 1 ;; esac
if [ -e "$destination" ] || [ -L "$destination" ]; then exit 3; fi
parent=$(dirname -- "$destination")
mkdir -p -m 0700 -- "$parent"
temporary=$(mktemp "$parent/.guest-bootstrap.XXXXXXXX")
trap 'rm -f -- "$temporary"' EXIT HUP INT TERM
cat > "$temporary"
# A hard link publishes atomically without replacing an existing file, even on a race.
ln -- "$temporary" "$destination"
`

type account struct {
	uid, gid int
	home     string
}

// parseAccount accepts only ordinary login accounts from a getent passwd line.
func parseAccount(line, user string) (account, error) {
	fields := strings.Split(strings.TrimSpace(line), ":")
	if len(fields) != 7 || fields[0] != user {
		return account{}, errors.New("Unexpected guest account")
	}
	uid, err1 := strconv.Atoi(fields[2])
	gid, err2 := strconv.Atoi(fields[3])
	if err1 != nil || err2 != nil {
		return account{}, errors.New("Unexpected guest account")
	}
	home, shell := fields[5], path.Base(fields[6])
	// ponytail: standard login UID range; use declared account metadata if low-UID logins are needed.
	if uid < 1000 || shell == "nologin" || shell == "false" || !strings.HasPrefix(home, "/") || home == "/" {
		return account{}, errors.New("Only ordinary guest login accounts may be bootstrapped")
	}
	return account{uid, gid, home}, nil
}

func guestAccount(name, kind, user string) (account, error) {
	if !guestUser.MatchString(user) {
		return account{}, errors.New("Invalid guest username")
	}
	if err := requireRunning(name, kind); err != nil {
		return account{}, err
	}
	line, err := run(guest(name, []string{"getent", "passwd", user}, nil, false), true, nil)
	if err != nil {
		return account{}, err
	}
	return parseAccount(line, user)
}

func passwd(name, kind, user string) error {
	if _, err := guestAccount(name, kind, user); err != nil {
		return err
	}
	out, err := run(guest(name, []string{"passwd", "--status", "--", user}, nil, false), true, nil)
	if err != nil {
		return err
	}
	status := strings.Fields(out)
	if len(status) < 2 || status[0] != user || (status[1] != "P" && status[1] != "L" && status[1] != "NP") {
		return errors.New("Unexpected guest password status")
	}
	if status[1] == "P" {
		fmt.Println("Existing password preserved")
		return nil
	}
	// L can also mean a locked *existing* hash; never replace that authentication.
	if _, err := run(guest(name, []string{"awk", "-F:", "-v", "login=" + user,
		`$1 == login && ($2 == "" || $2 == "!" || $2 == "!!" || $2 == "*") { unset = 1 } END { exit !unset }`,
		"/etc/shadow"}, nil, false), false, nil); err != nil {
		return err
	}
	if !isTerminal(os.Stdin) {
		return errors.New("Password setup requires a terminal; do not pipe passwords")
	}
	_, err = run(guest(name, []string{"passwd", "--", user}, nil, true), false, nil)
	return err
}

// validDestination accepts only relative home paths without empty or dot segments.
func validDestination(destination string) bool {
	if strings.HasPrefix(destination, "/") {
		return false
	}
	for _, part := range strings.Split(destination, "/") {
		if part == "" || part == "." || part == ".." {
			return false
		}
	}
	return true
}

func pushFile(cmd command, kind string) error {
	user, err := guestAccount(cmd.guest, kind, cmd.user)
	if err != nil {
		return err
	}
	if !validDestination(cmd.destination) {
		return errors.New("Destination must be a relative home path without dot segments")
	}
	unit := cmd.systemUnit + cmd.userUnit
	if unit != "" && !serviceUnit.MatchString(unit) {
		return errors.New("Expected a service unit name")
	}
	source, err := os.OpenFile(cmd.source, os.O_RDONLY|syscall.O_NOFOLLOW|syscall.O_NONBLOCK, 0)
	if err != nil {
		return err
	}
	defer source.Close()
	info, err := source.Stat()
	if err != nil {
		return err
	}
	if !info.Mode().IsRegular() || info.Mode().Perm()&0o077 != 0 {
		return errors.New("Source must be a private regular file (0600 or stricter)")
	}
	argv := guest(cmd.guest, []string{"/bin/sh", "-c", installScript, "guest-bootstrap", user.home, path.Join(user.home, cmd.destination)},
		&identity{user.uid, user.gid}, false)
	install := exec.Command(argv[0], argv[1:]...)
	install.Stdin, install.Stdout, install.Stderr = source, os.Stdout, os.Stderr
	if err := install.Run(); err != nil {
		var exit *exec.ExitError
		if errors.As(err, &exit) && exit.ExitCode() == 3 {
			fmt.Println("Existing credential file preserved; service not changed")
			return nil
		}
		return errors.New("Guest credential installation failed")
	}
	switch {
	case cmd.systemUnit != "":
		_, err = run(guest(cmd.guest, []string{"systemctl", "start", "--", unit}, nil, false), false, nil)
	case cmd.userUnit != "":
		_, err = run(guest(cmd.guest, []string{"env", "XDG_RUNTIME_DIR=/run/user/" + strconv.Itoa(user.uid),
			"systemctl", "--user", "start", "--", unit}, &identity{user.uid, user.gid}, false), false, nil)
	}
	if err != nil {
		return err
	}
	fmt.Println("Credential installed; no existing authentication was replaced")
	return nil
}
