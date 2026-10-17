// pipeasio-register-steam-prefixes registers PipeASIO in launched Steam Proton prefixes through each game's own runner.
package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"syscall"
)

const registryCLSID = "{2D3CA9E2-1193-4C5D-B5FD-38798F3DC074}"

var (
	pipeasioSection = regexp.MustCompile(`(?mi)^\[Software\\\\ASIO\\\\PipeASIO\][^\n]*\n([^\[]*)`)
	pipeasioCLSID   = regexp.MustCompile(`(?mi)^"CLSID"="` + regexp.QuoteMeta(registryCLSID) + `"$`)
	// Native session daemons whose environment is unreadable but never hold a Wine prefix.
	knownDaemons = []string{"systemd", "(sd-pam)", "Hyprland", ".Hyprland-wrapp", "ssh-agent"}
)

// target is one entry of `pipeasio-manage list`.
type target struct {
	Kind     string `json:"kind"`
	Prefix   string `json:"prefix"`
	Runner   string `json:"runner"`
	Error    string `json:"error"`
	Metadata struct {
		RuntimeReady bool `json:"runtime_ready"`
	} `json:"metadata"`
}

func logf(format string, args ...any) { fmt.Fprintf(os.Stderr, "pipeasio: "+format+"\n", args...) }

func main() {
	if len(os.Args) > 1 && os.Args[1] == "proton-run" {
		protonRun(os.Args[2:])
	}
	skipRegistered := flag.Bool("skip-registered", false, "Skip prefixes whose registry and copied driver match this package.")
	noRuntimeDownload := flag.Bool("no-runtime-download", false, "Defer prefixes whose umu Steam Runtime has not been downloaded yet.")
	flag.Parse()
	if flag.NArg() != 0 {
		flag.Usage()
		os.Exit(2)
	}
	os.Exit(run(*skipRegistered, *noRuntimeDownload))
}

// protonRun is the WINE command for pipeasio-register: umu expects compatdata, while the
// registration needs its pfx directory.
func protonRun(args []string) {
	umu, err := exec.LookPath("umu-run")
	if err == nil {
		os.Setenv("WINEPREFIX", os.Getenv("STEAM_COMPAT_DATA_PATH"))
		err = syscall.Exec(umu, append([]string{umu}, args...), os.Environ())
	}
	logf("%v", err)
	os.Exit(1)
}

func run(skipRegistered, noRuntimeDownload bool) int {
	register, err := exec.LookPath("pipeasio-register")
	if err != nil {
		logf("missing pipeasio-register: %v", err)
		return 1
	}
	output, err := exec.Command("pipeasio-manage", "list").Output()
	if err != nil {
		logf("could not discover owning Proton runners: %v", err)
		return 1
	}
	var list struct {
		Targets []target `json:"targets"`
	}
	if err := json.Unmarshal(output, &list); err != nil {
		logf("could not discover owning Proton runners: %v", err)
		return 1
	}
	prefixes, targets := steamPrefixes(list.Targets)
	if len(prefixes) == 0 {
		logf("no existing Steam Proton prefixes found")
		return 0
	}

	driver := os.Getenv("PIPEASIO_DRIVER_DLL")
	registered, skipped, failed := 0, 0, 0
	for _, prefix := range prefixes {
		if skipRegistered && prefixIsCurrent(prefix, driver) {
			skipped++
			logf("already registered in %s, skipping", prefix)
			continue
		}
		t := targets[prefix]
		reason := ""
		switch {
		case t.Error != "":
			reason = t.Error
		case t.Runner == "":
			reason = "owning Proton is not installed"
		case noRuntimeDownload && !t.Metadata.RuntimeReady:
			reason = "run pipeasio-register-steam-prefixes manually to download the umu runtime"
		case prefixIsBusy(prefix):
			reason = "close applications using this prefix, then rerun this command"
		}
		if reason != "" {
			skipped++
			logf("deferred %s: %s", prefix, reason)
			continue
		}
		if err := registerPrefix(register, prefix, t); err != nil {
			failed++
			logf("failed to register %s: %v", prefix, err)
		} else {
			registered++
		}
	}

	logf("registered %d Steam prefixes", registered)
	if skipped > 0 {
		logf("skipped/deferred %d prefix(es)", skipped)
	}
	if failed > 0 {
		logf("%d prefix(es) failed, see messages above", failed)
		return 1
	}
	return 0
}

func canonical(path string) string {
	absolute, err := filepath.Abs(path)
	if err != nil {
		return path
	}
	if resolved, err := filepath.EvalSymlinks(absolute); err == nil {
		return resolved
	}
	return absolute
}

// steamPrefixes keeps launched Steam prefixes (an existing pfx directory), once each, in path order.
func steamPrefixes(list []target) ([]string, map[string]target) {
	targets := map[string]target{}
	prefixes := []string{}
	for _, t := range list {
		if t.Kind != "steam" || t.Prefix == "" {
			continue
		}
		prefix := canonical(t.Prefix)
		if info, err := os.Stat(prefix); err != nil || !info.IsDir() {
			continue
		}
		if _, seen := targets[prefix]; seen {
			continue
		}
		targets[prefix] = t
		prefixes = append(prefixes, prefix)
	}
	slices.Sort(prefixes)
	return prefixes, targets
}

// prefixIsCurrent reads Wine's text registry instead of starting (and migrating) the prefix.
func prefixIsCurrent(prefix, driver string) bool {
	registry, err := os.ReadFile(filepath.Join(prefix, "system.reg"))
	if err != nil {
		return false
	}
	section := pipeasioSection.FindSubmatch(registry)
	if section == nil || !pipeasioCLSID.Match(section[1]) {
		return false
	}
	expected, err := os.ReadFile(driver)
	if err != nil {
		return false
	}
	copied, err := os.ReadFile(filepath.Join(prefix, "drive_c", "windows", "system32", "pipeasio64.dll"))
	return err == nil && bytes.Equal(expected, copied)
}

func prefixIsBusy(prefix string) bool {
	entries, err := os.ReadDir("/proc")
	if err != nil {
		return true
	}
	uid := uint32(os.Getuid())
	for _, entry := range entries {
		if _, err := strconv.Atoi(entry.Name()); err != nil {
			continue
		}
		process := filepath.Join("/proc", entry.Name())
		info, err := os.Stat(process)
		if err != nil {
			continue
		}
		if stat, ok := info.Sys().(*syscall.Stat_t); !ok || stat.Uid != uid {
			continue
		}
		environment, err := os.ReadFile(filepath.Join(process, "environ"))
		switch {
		case errors.Is(err, fs.ErrPermission):
			comm, _ := os.ReadFile(filepath.Join(process, "comm"))
			if !slices.Contains(knownDaemons, strings.TrimSpace(string(comm))) {
				return true
			}
		case err != nil:
			// The process exited meanwhile.
		default:
			for _, variable := range bytes.Split(environment, []byte{0}) {
				if value, ok := bytes.CutPrefix(variable, []byte("WINEPREFIX=")); ok && canonical(string(value)) == prefix {
					return true
				}
			}
		}
	}
	return false
}

// registrationEnvironment never inherits another game's Proton settings or bypasses the upstream guard.
func registrationEnvironment(base []string, prefix, runner, protonRun string) []string {
	dropped := []string{"WINEARCH", "WINEDLLOVERRIDES", "WINEDLLPATH", "WINELOADER", "WINESERVER", "PIPEASIO_REGISTER_WITHOUT_LOADING"}
	environment := []string{}
	for _, variable := range base {
		key, _, _ := strings.Cut(variable, "=")
		if strings.HasPrefix(key, "STEAM_COMPAT_") || strings.HasPrefix(key, "UMU_") || strings.HasPrefix(key, "PROTON") || slices.Contains(dropped, key) {
			continue
		}
		environment = append(environment, variable)
	}
	return append(environment,
		"WINEPREFIX="+prefix,
		"WINE="+protonRun,
		"STEAM_COMPAT_DATA_PATH="+filepath.Dir(prefix),
		"PROTONPATH="+runner,
		"GAMEID=umu-0",
		"PROTONFIXES_DISABLE=1",
		"UMU_RUNTIME_UPDATE=0",
		"PROTON_VERB=waitforexitandrun",
	)
}

// registerPrefix restores the previous driver if the registration fails.
func registerPrefix(register, prefix string, t target) error {
	logf("registering %s through %s", prefix, t.Runner)
	info, err := os.Stat(prefix)
	if err != nil {
		return err
	}
	if stat, ok := info.Sys().(*syscall.Stat_t); !ok || stat.Uid != uint32(os.Getuid()) {
		return errors.New("prefix must belong to this user")
	}
	dll := filepath.Join(prefix, "drive_c", "windows", "system32", "pipeasio64.dll")
	backup := ""
	if driver, err := os.Lstat(dll); err == nil {
		if driver.Mode()&fs.ModeSymlink != 0 {
			return errors.New("driver must not be a symlink")
		}
		if backup, err = backupFile(dll, driver); err != nil {
			return err
		}
		defer os.Remove(backup)
	}
	cmd := exec.Command(register)
	cmd.Env = registrationEnvironment(os.Environ(), prefix, t.Runner, os.Getenv("PIPEASIO_PROTON_RUN"))
	cmd.Stdout, cmd.Stderr = os.Stderr, os.Stderr
	if err := cmd.Run(); err != nil {
		if backup != "" {
			if restoreErr := os.Rename(backup, dll); restoreErr != nil {
				return errors.Join(err, restoreErr)
			}
		}
		return err
	}
	return nil
}

func backupFile(path string, info fs.FileInfo) (string, error) {
	source, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer source.Close()
	backup, err := os.CreateTemp(filepath.Dir(path), ".pipeasio-backup-")
	if err != nil {
		return "", err
	}
	_, err = io.Copy(backup, source)
	err = errors.Join(err, backup.Chmod(info.Mode().Perm()), backup.Close())
	if err == nil {
		err = os.Chtimes(backup.Name(), info.ModTime(), info.ModTime())
	}
	if err != nil {
		os.Remove(backup.Name())
		return "", err
	}
	return backup.Name(), nil
}
