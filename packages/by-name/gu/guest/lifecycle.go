package main

import (
	"bufio"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"maps"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"syscall"
	"time"
	"unsafe"
)

var storePath = regexp.MustCompile(`^/nix/store/[a-z0-9]{32}-[^/\s]+$`)

const agentTimeout = 300 * time.Second

// flake validates the selected guest configuration against the declared
// instance type and returns its attribute path plus the nix build argv prefix.
func flake(cfg *config, name string, build buildOptions) (string, []string, error) {
	file, err := filepath.EvalSymlinks(cfg.FlakeFile)
	if err == nil {
		file, err = filepath.Abs(file)
	}
	if err != nil {
		return "", nil, err
	}
	if info, err := os.Stat(file); err != nil || filepath.Base(file) != "flake.nix" || !info.Mode().IsRegular() {
		return "", nil, errors.New("flakeFile must name an existing flake.nix")
	}
	nixArgs := []string{"--no-write-lock-file"}
	for _, pair := range build.overrides {
		nixArgs = append(nixArgs, "--override-input", pair[0], pair[1])
	}
	configuration := "path:" + filepath.Dir(file) + "#nixosConfigurations." + name + ".config"
	shape, err := run(append(append([]string{"nix", "eval"}, nixArgs...), "--json", configuration,
		"--apply", "c: { isContainer = c.boot.isContainer; incusAgent = c.virtualisation.incus.agent.enable; }"), true, nil)
	if err != nil {
		return "", nil, err
	}
	kind := cfg.Guests[name].Type
	if !guestShape([]byte(shape), kind) {
		if kind == container {
			return "", nil, errors.New("Selected flake configuration must be an Incus NixOS container guest (boot.isContainer)")
		}
		return "", nil, errors.New("Selected flake configuration must be an Incus NixOS VM guest (not a container, with the Incus agent enabled)")
	}
	command := append(append([]string{"nix", "build"}, nixArgs...), "--print-out-paths")
	if build.maxJobs != nil {
		command = append(command, "--max-jobs", strconv.Itoa(*build.maxJobs))
	}
	if build.cores != nil {
		command = append(command, "--cores", strconv.Itoa(*build.cores))
	}
	return configuration, command, nil
}

func guestShape(data []byte, kind string) bool {
	var shape map[string]any
	if json.Unmarshal(data, &shape) != nil || len(shape) != 2 {
		return false
	}
	if _, ok := shape["incusAgent"].(bool); !ok {
		return false
	}
	if kind == container {
		return shape["isContainer"] == true
	}
	return shape["isContainer"] == false && shape["incusAgent"] == true
}

// imageFile finds exactly one metadata tarball (any depth, under a tarball
// directory), or one top-level root image with the given extension.
func imageFile(root, extension string) (string, error) {
	var matches []string
	if extension == "" {
		err := filepath.WalkDir(root, func(path string, entry fs.DirEntry, err error) error {
			if err != nil {
				return err
			}
			if !entry.IsDir() && filepath.Base(filepath.Dir(path)) == "tarball" && strings.HasSuffix(entry.Name(), ".tar.xz") {
				matches = append(matches, path)
			}
			return nil
		})
		if err != nil {
			return "", err
		}
	} else {
		found, err := filepath.Glob(filepath.Join(root, "*"+extension))
		if err != nil {
			return "", err
		}
		matches = found
	}
	if len(matches) != 1 {
		return "", errors.New("Expected exactly one Incus image archive under " + root)
	}
	return matches[0], nil
}

// fingerprint is the Incus split-image fingerprint: SHA-256(metadata archive || root image bytes).
func fingerprint(paths ...string) (string, error) {
	digest := sha256.New()
	for _, path := range paths {
		file, err := os.Open(path)
		if err != nil {
			return "", err
		}
		_, err = io.Copy(digest, file)
		file.Close()
		if err != nil {
			return "", err
		}
	}
	return hex.EncodeToString(digest.Sum(nil)), nil
}

func create(name string, definition guestDefinition, cfg *config, build buildOptions) error {
	configuration, command, err := flake(cfg, name, build)
	if err != nil {
		return err
	}
	image, err := importImage(configuration, command, definition.Type)
	if err != nil {
		return err
	}
	launch := []string{"launch", image, name, "--quiet"}
	if definition.Type == virtualMachine {
		launch = append(launch, "--vm")
	}
	_, launchErr := incus(false, strings.NewReader(string(definition.LaunchConfig)), launch...)
	// Existing guests are updated by rebuild, never from the creation image.
	_, deleteErr := incus(false, nil, "image", "delete", image)
	if launchErr != nil {
		return launchErr
	}
	return deleteErr
}

// rootImage is the system.build output and file extension of the guest root image.
func rootImage(kind string) (string, string) {
	if kind == container {
		return "squashfs", ".squashfs"
	}
	return "qemuImage", ".qcow2"
}

func importImage(configuration string, command []string, kind string) (string, error) {
	directory, err := os.MkdirTemp("", "guest-image-")
	if err != nil {
		return "", err
	}
	// Out-links keep the image outputs alive only until the import finishes.
	defer os.RemoveAll(directory)
	output, extension := rootImage(kind)
	var outputs [2]string
	for i, part := range [2][2]string{{"metadata", "metadata"}, {"root", output}} {
		out, err := run(append(append([]string{}, command...), "--out-link", filepath.Join(directory, part[0]), configuration+".system.build."+part[1]), true, nil)
		if err != nil {
			return "", err
		}
		outputs[i] = out
	}
	metadata, err := imageFile(outputs[0], "")
	if err != nil {
		return "", err
	}
	rootfs, err := imageFile(outputs[1], extension)
	if err != nil {
		return "", err
	}
	id, err := fingerprint(metadata, rootfs)
	if err != nil {
		return "", err
	}
	out, err := incus(true, nil, "image", "list", "--format=json")
	if err != nil {
		return "", err
	}
	images, ok := objectList([]byte(out))
	if !ok {
		return "", errors.New("Unexpected Incus image list")
	}
	for _, item := range images {
		if item["fingerprint"] == id {
			if item["type"] != kind {
				return "", errors.New("Matching Incus image must have " + kind + " type")
			}
			return id, nil
		}
	}
	if _, err := incus(false, nil, "image", "import", metadata, rootfs); err != nil {
		return "", err
	}
	return id, nil
}

// deviceValues renders the non-type properties as key=value arguments.
func deviceValues(fields map[string]json.RawMessage) []string {
	var values []string
	for _, key := range slices.Sorted(maps.Keys(fields)) {
		if key == "type" {
			continue
		}
		var text string
		if json.Unmarshal(fields[key], &text) != nil {
			text = string(compact(fields[key]))
		}
		values = append(values, key+"="+text)
	}
	return values
}

func syncDevices(name string, definition guestDefinition) error {
	if len(definition.ManagedDeviceNames) == 0 {
		return nil
	}
	devices, err := definition.devices()
	if err != nil {
		return err
	}
	out, err := incus(true, nil, "config", "device", "list", name)
	if err != nil {
		return err
	}
	existing := strings.Split(out, "\n")
	for _, device := range definition.ManagedDeviceNames {
		fields, ok := devices[device]
		if !ok {
			return errors.New("managed device " + device + " is missing from launchConfig.devices")
		}
		values := deviceValues(fields)
		if slices.Contains(existing, device) {
			if len(values) > 0 {
				if _, err := incus(false, nil, append([]string{"config", "device", "set", name, device}, values...)...); err != nil {
					return err
				}
			}
			continue
		}
		var kind string
		if json.Unmarshal(fields["type"], &kind) != nil || kind == "" {
			return errors.New("managed device " + device + " needs a string type")
		}
		if _, err := incus(false, nil, append([]string{"config", "device", "add", name, device, kind}, values...)...); err != nil {
			return err
		}
	}
	return nil
}

// start creates a missing guest, upserts managed devices, starts it and waits until incus exec works.
func start(name string, cfg *config, build buildOptions, createMissing bool) error {
	definition := cfg.Guests[name]
	current, err := instance(name, definition.Type)
	if err != nil {
		return err
	}
	if current == nil {
		if !createMissing {
			return errors.New("Guest " + name + " does not exist; create it with: guest " + name + " boot")
		}
		if err := create(name, definition, cfg, build); err != nil {
			return err
		}
	} else if current["status"] != "Running" && current["status"] != "Stopped" {
		return fmt.Errorf("Refusing to change an Incus instance in state %v", current["status"])
	}
	if err := syncDevices(name, definition); err != nil {
		return err
	}
	started := current == nil || current["status"] == "Stopped"
	if current != nil && started {
		if _, err := incus(false, nil, "start", name); err != nil {
			return err
		}
	}
	deadline := time.Now().Add(agentTimeout)
	for {
		probe := guest(name, []string{"true"}, nil, false)
		if exec.Command(probe[0], probe[1:]...).Run() == nil {
			break
		}
		if time.Now().After(deadline) {
			return errors.New("Guest " + name + " did not accept incus exec")
		}
		time.Sleep(2 * time.Second)
	}
	if started && definition.CredentialUnit != nil {
		if _, err := run([]string{"systemctl", "restart", "--", *definition.CredentialUnit}, false, nil); err != nil {
			return errors.New("Credential delivery failed; run: systemctl restart " + *definition.CredentialUnit)
		}
	}
	return nil
}

func stop(name, kind string) error {
	current, err := instance(name, kind)
	if err != nil {
		return err
	}
	if current == nil {
		return errors.New("Guest " + name + " does not exist")
	}
	if current["status"] == "Stopped" {
		fmt.Println(name + " is already stopped")
		return nil
	}
	_, err = incus(false, nil, "stop", name)
	return err
}

func deleteGuest(name, kind string) error {
	current, err := instance(name, kind)
	if err != nil {
		return err
	}
	if current == nil {
		fmt.Println(name + " does not exist")
		return nil
	}
	if current["status"] != "Stopped" {
		return errors.New("Stop the guest first: guest " + name + " stop")
	}
	if !isTerminal(os.Stdin) {
		return errors.New("Deletion requires a terminal confirmation")
	}
	fmt.Print("Type " + name + " to permanently delete the guest and its volumes: ")
	answer, _ := bufio.NewReader(os.Stdin).ReadString('\n')
	if strings.TrimSuffix(answer, "\n") != name {
		return errors.New("Confirmation did not match; nothing was deleted")
	}
	_, err = incus(false, nil, "delete", name)
	return err
}

func transfer(name, system string) error {
	out, err := run([]string{"nix-store", "--query", "--requisites", system}, true, nil)
	if err != nil {
		return err
	}
	paths := strings.Split(out, "\n")
	if out == "" || slices.ContainsFunc(paths, func(path string) bool { return !storePath.MatchString(path) }) {
		return errors.New("Invalid closure path list")
	}
	// ponytail: one argv list; batch transport if closures approach the OS argument-size limit.
	out, err = run(guest(name, append([]string{"nix-store", "--check-validity", "--print-invalid"}, paths...), nil, false), true, nil)
	if err != nil {
		return err
	}
	var missing []string
	if out != "" {
		missing = strings.Split(out, "\n")
	}
	for _, path := range missing {
		if !slices.Contains(paths, path) {
			return errors.New("Guest returned paths outside the built closure")
		}
	}
	if len(missing) == 0 {
		return nil
	}
	exporter := exec.Command("nix-store", append([]string{"--export"}, missing...)...)
	exporter.Stderr = os.Stderr
	stream, err := exporter.StdoutPipe()
	if err != nil {
		return err
	}
	if err := exporter.Start(); err != nil {
		return err
	}
	importArgv := guest(name, []string{"nix-store", "--import"}, nil, false)
	importer := exec.Command(importArgv[0], importArgv[1:]...)
	importer.Stdin, importer.Stdout, importer.Stderr = stream, os.Stdout, os.Stderr
	importErr := importer.Run()
	stream.Close()
	exportErr := exporter.Wait()
	if importErr != nil {
		return &commandError{importArgv, importErr}
	}
	if exportErr != nil {
		return errors.New("Closure export failed; activation was not attempted")
	}
	return nil
}

func rebuild(cmd command, cfg *config) error {
	name, kind := cmd.guest, cfg.Guests[cmd.guest].Type
	applying := slices.Contains(apply, cmd.action)
	if cmd.rollback && !applying {
		return errors.New("--rollback requires dry-activate, test, switch or boot")
	}
	native := []string{"/run/current-system/sw/bin/nixos-rebuild", cmd.action, "--no-reexec"}
	if cmd.action == "list-generations" {
		if err := requireRunning(name, kind); err != nil {
			return err
		}
		_, err := run(guest(name, native, nil, false), false, nil)
		return err
	}
	if applying {
		if err := start(name, cfg, cmd.build, !cmd.rollback); err != nil {
			return err
		}
		if cmd.rollback {
			_, err := run(guest(name, append(native, "--rollback"), nil, false), false, nil)
			return err
		}
	}
	configuration, command, err := flake(cfg, name, cmd.build)
	if err != nil {
		return err
	}
	installable := configuration + ".system.build.toplevel"
	if cmd.action == "dry-build" || cmd.action == "dry-run" {
		_, err := run(append(command, "--no-link", "--dry-run", installable), false, nil)
		return err
	}
	system, err := run(append(command, "--no-link", installable), true, nil)
	if err != nil {
		return err
	}
	if !storePath.MatchString(system) || !strings.Contains(system, "-nixos-system-") {
		return errors.New("Build must return exactly one NixOS system store path")
	}
	if cmd.action == "build" {
		fmt.Println(system)
		return nil
	}
	if err := transfer(name, system); err != nil {
		return err
	}
	// Native rebuild owns profile/generation semantics: test is temporary, boot does not activate.
	_, err = run(guest(name, append(native, "--store-path", system), nil, false), false, nil)
	return err
}

func isTerminal(file *os.File) bool {
	var state syscall.Termios
	_, _, errno := syscall.Syscall(syscall.SYS_IOCTL, file.Fd(), syscall.TCGETS, uintptr(unsafe.Pointer(&state)))
	return errno == 0
}
