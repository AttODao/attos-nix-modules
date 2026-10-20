// Interactive root helper storing a login PIN as a crypt(3) hash in a pam_userdb database.
package main

import (
	"bufio"
	"bytes"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"regexp"
	"strings"
	"syscall"
)

const (
	// The NixOS module sets this to the account the PAM stack accepts a PIN for.
	userVariable = "LOGIN_PIN_USER"
	directory    = "/etc/security/login-pin"
)

var pinPattern = regexp.MustCompile(`^[0-9]{6}$`)

func validPIN(pin string) bool { return pinPattern.MatchString(pin) }

// pam_userdb reads a Berkeley DB hash keyed by user name with a crypt(3) value.
func dbLoadInput(user, hash string) string { return user + "\n" + hash + "\n" }

// allowedUser resolves the only account a PIN may be stored for: the optional
// argument must match the configured user, and an unset variable refuses every user.
func allowedUser(configured string, arguments []string) (string, error) {
	if len(arguments) > 1 {
		return "", errors.New("usage: set-login-pin [user]")
	}
	if configured == "" {
		return "", errors.New(userVariable + " is not set; the login-pin module configures it")
	}
	if len(arguments) == 1 && arguments[0] != "" && arguments[0] != configured {
		return "", fmt.Errorf("user '%s' is not enabled for login PIN", arguments[0])
	}
	return configured, nil
}

func stty(argument string) {
	command := exec.Command("stty", argument)
	command.Stdin = os.Stdin
	_ = command.Run()
}

// readLine mirrors `read -r`: no backslash processing, surrounding IFS whitespace removed.
func readLine(reader *bufio.Reader) (string, error) {
	line, err := reader.ReadString('\n')
	if err != nil && !(errors.Is(err, io.EOF) && line != "") {
		return "", errors.New("could not read PIN")
	}
	return strings.Trim(line, " \t\n"), nil
}

func hashPIN(pin string) (string, error) {
	command := exec.Command("mkpasswd", "--method=yescrypt", "--stdin")
	// The PIN never appears in process arguments.
	command.Stdin = strings.NewReader(pin + "\n")
	var output bytes.Buffer
	command.Stdout = &output
	command.Stderr = os.Stderr
	if command.Run() != nil {
		return "", errors.New("could not hash PIN")
	}
	hash := strings.TrimSpace(output.String())
	if !strings.HasPrefix(hash, "$y$") || strings.ContainsAny(hash, "\n\r") {
		return "", errors.New("unexpected hash format")
	}
	return hash, nil
}

func store(dir, user, hash string) error {
	syscall.Umask(0o077)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	if os.Geteuid() == 0 {
		if err := os.Chown(dir, 0, 0); err != nil {
			return err
		}
	}
	if err := os.Chmod(dir, 0o700); err != nil {
		return err
	}
	temporary, err := os.MkdirTemp(dir, ".pins.")
	if err != nil {
		return err
	}
	defer os.RemoveAll(temporary)
	database := filepath.Join(temporary, "pins.db")
	command := exec.Command("db_load", "-T", "-t", "hash", database)
	command.Stdin = strings.NewReader(dbLoadInput(user, hash))
	command.Stderr = os.Stderr
	if command.Run() != nil {
		return errors.New("could not write PIN database")
	}
	if err := os.Chmod(database, 0o600); err != nil {
		return err
	}
	return os.Rename(database, filepath.Join(dir, "pins.db"))
}

func set(arguments []string) error {
	user, err := allowedUser(os.Getenv(userVariable), arguments)
	if err != nil {
		return err
	}
	if os.Geteuid() != 0 {
		return fmt.Errorf("run as root, for example: sudo set-login-pin %s", user)
	}

	stty("-echo")
	interrupts := make(chan os.Signal, 1)
	signal.Notify(interrupts, os.Interrupt, syscall.SIGTERM)
	go func() {
		<-interrupts
		stty("echo")
		fmt.Fprintln(os.Stderr)
		os.Exit(130)
	}()
	reader := bufio.NewReader(os.Stdin)
	fmt.Fprintf(os.Stderr, "New 6-digit PIN for %s: ", user)
	first, err := readLine(reader)
	var second string
	if err == nil {
		fmt.Fprint(os.Stderr, "\nConfirm 6-digit PIN: ")
		second, err = readLine(reader)
	}
	stty("echo")
	signal.Stop(interrupts)
	fmt.Fprintln(os.Stderr)
	if err != nil {
		return err
	}
	if first != second {
		return errors.New("PINs do not match")
	}
	if !validPIN(first) {
		return errors.New("PIN must be exactly 6 digits")
	}
	hash, err := hashPIN(first)
	if err != nil {
		return err
	}
	if err := store(directory, user, hash); err != nil {
		return err
	}
	fmt.Println("PIN updated for " + user)
	return nil
}

func main() {
	var err error
	if len(os.Args) >= 2 && os.Args[1] == "set" {
		err = set(os.Args[2:])
	} else {
		err = errors.New("usage: login-pin set [user]")
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, "error: "+err.Error())
		os.Exit(1)
	}
}
