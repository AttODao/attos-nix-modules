// guest manages declared local Incus guests (KVM virtual machines and system
// containers): create, start, stop, delete and rebuild them, deliver root
// credentials, and install initial guest authentication without replacing
// existing authentication.
package main

import (
	"errors"
	"fmt"
	"os"
	"slices"
	"strconv"
	"strings"
)

const usage = `usage: guest --config FILE GUEST COMMAND [ARGS]

commands:
  boot [BUILD]                  create the guest from the flake if missing, then start it
  stop                          shut the guest down
  delete                        delete a stopped guest and its volumes after confirmation
  rebuild [ACTION] [FLAKE] [BUILD] [--rollback]
                                build and apply the guest system like nixos-rebuild
                                (ACTION: ` + "build, dry-build, dry-run, dry-activate, test, switch (default), boot, list-generations" + `)
  passwd USER                   set an unset/locked login password interactively
  push-file USER SOURCE DEST [--system-unit UNIT | --user-unit UNIT]
                                install a private file under the user's home, without overwriting
  deliver-credentials           deliver declared root credentials (used by the host unit)

  guest preseed-condition POOL  ExecCondition guard for create-only Incus preseed

BUILD options: --flake REF, --max-jobs N, --cores N, --override-input NAME REFERENCE

FLAKE / --flake REF selects the flake holding nixosConfigurations.GUEST (default: the
configured one, e.g. a registry alias). The latest revision is fetched once per invocation
(--refresh on the first evaluation); the following builds reuse that revision.
`

var (
	actions = []string{"build", "dry-build", "dry-run", "dry-activate", "test", "switch", "boot", "list-generations"}
	apply   = []string{"dry-activate", "test", "switch", "boot"}
)

type buildOptions struct {
	maxJobs, cores *int
	overrides      [][2]string
	flake          string
}

type command struct {
	guest, name string
	build       buildOptions
	// rebuild
	action   string
	rollback bool
	// passwd / push-file
	user, source, destination, systemUnit, userUnit string
}

// usageError is reported with exit status 2, like other argument errors.
type usageError struct{ msg string }

func (e usageError) Error() string { return e.msg }

func main() {
	os.Exit(realMain(os.Args[1:]))
}

func realMain(args []string) int {
	configPath := ""
	if len(args) >= 2 && args[0] == "--config" {
		configPath, args = args[1], args[2:]
	} else if len(args) >= 1 && strings.HasPrefix(args[0], "--config=") {
		configPath, args = strings.TrimPrefix(args[0], "--config="), args[1:]
	}
	if len(args) > 0 && args[0] == "preseed-condition" {
		code, err := preseedCondition(args[1:])
		if err != nil {
			fmt.Fprintln(os.Stderr, "Incus preseed check failed: "+err.Error())
			// An ExecCondition daemon/parser failure must fail the unit instead of permitting initialization.
			return 255
		}
		return code
	}
	if len(args) == 0 || args[0] == "-h" || args[0] == "--help" {
		fmt.Print(usage)
		if len(args) == 0 {
			return 2
		}
		return 0
	}
	if configPath == "" {
		fmt.Fprintln(os.Stderr, "guest: --config is required")
		return 2
	}
	cfg, err := loadConfig(configPath)
	if err != nil {
		fmt.Fprintln(os.Stderr, "guest: "+err.Error())
		return 1
	}
	cmd, err := parseCommand(args, cfg)
	if err != nil {
		fmt.Fprintln(os.Stderr, "guest: "+err.Error())
		fmt.Fprint(os.Stderr, usage)
		return 2
	}
	if err := execute(cmd, cfg); err != nil {
		var cmdErr *commandError
		if (cmd.name == "passwd" || cmd.name == "push-file") && errors.As(err, &cmdErr) {
			fmt.Fprintln(os.Stderr, "guest: Guest operation failed; existing authentication was not replaced")
		} else {
			fmt.Fprintln(os.Stderr, "guest: "+err.Error())
		}
		return 1
	}
	return 0
}

func parseCommand(args []string, cfg *config) (command, error) {
	if len(args) < 2 {
		return command{}, usageError{"expected GUEST and COMMAND"}
	}
	cmd := command{guest: args[0], name: args[1]}
	if _, ok := cfg.Guests[cmd.guest]; !ok {
		names := cfg.names()
		return command{}, usageError{fmt.Sprintf("unknown guest %q (choose from %s)", cmd.guest, strings.Join(names, ", "))}
	}
	rest := args[2:]
	var positional []string
	takesBuild := cmd.name == "boot" || cmd.name == "rebuild"
	for i := 0; i < len(rest); i++ {
		arg := rest[i]
		value := func() (string, error) {
			if i+1 >= len(rest) {
				return "", usageError{arg + " requires a value"}
			}
			i++
			return rest[i], nil
		}
		switch {
		case takesBuild && (arg == "--max-jobs" || arg == "--cores"):
			v, err := value()
			if err != nil {
				return command{}, err
			}
			n, err := strconv.Atoi(v)
			if err != nil {
				return command{}, usageError{arg + " expects an integer"}
			}
			if n < 0 {
				return command{}, usageError{"--max-jobs and --cores must be nonnegative"}
			}
			if arg == "--max-jobs" {
				cmd.build.maxJobs = &n
			} else {
				cmd.build.cores = &n
			}
		case takesBuild && arg == "--flake":
			v, err := value()
			if err != nil {
				return command{}, err
			}
			cmd.build.flake = v
		case takesBuild && arg == "--override-input":
			if i+2 >= len(rest) {
				return command{}, usageError{"--override-input requires NAME and REFERENCE"}
			}
			cmd.build.overrides = append(cmd.build.overrides, [2]string{rest[i+1], rest[i+2]})
			i += 2
		case cmd.name == "rebuild" && arg == "--rollback":
			cmd.rollback = true
		case cmd.name == "push-file" && (arg == "--system-unit" || arg == "--user-unit"):
			v, err := value()
			if err != nil {
				return command{}, err
			}
			if arg == "--system-unit" {
				cmd.systemUnit = v
			} else {
				cmd.userUnit = v
			}
		case strings.HasPrefix(arg, "-"):
			return command{}, usageError{"unrecognized argument " + arg}
		default:
			positional = append(positional, arg)
		}
	}
	switch cmd.name {
	case "boot", "stop", "delete", "deliver-credentials":
		if len(positional) != 0 {
			return command{}, usageError{cmd.name + " takes no positional arguments"}
		}
	case "rebuild":
		cmd.action = "switch"
		if len(positional) > 2 {
			return command{}, usageError{"rebuild takes at most ACTION and FLAKE"}
		}
		if len(positional) >= 1 {
			cmd.action = positional[0]
		}
		if len(positional) == 2 {
			if slices.Contains(actions, positional[1]) {
				return command{}, usageError{"rebuild takes at most one ACTION"}
			}
			if cmd.build.flake != "" {
				return command{}, usageError{"give FLAKE either positionally or with --flake"}
			}
			cmd.build.flake = positional[1]
		}
		if !slices.Contains(actions, cmd.action) {
			return command{}, usageError{"invalid rebuild action " + cmd.action}
		}
	case "passwd":
		if len(positional) != 1 {
			return command{}, usageError{"passwd expects USER"}
		}
		cmd.user = positional[0]
	case "push-file":
		if len(positional) != 3 {
			return command{}, usageError{"push-file expects USER SOURCE DEST"}
		}
		cmd.user, cmd.source, cmd.destination = positional[0], positional[1], positional[2]
		if cmd.systemUnit != "" && cmd.userUnit != "" {
			return command{}, usageError{"--system-unit and --user-unit are mutually exclusive"}
		}
	default:
		return command{}, usageError{"unknown command " + cmd.name}
	}
	return cmd, nil
}

func execute(cmd command, cfg *config) error {
	definition := cfg.Guests[cmd.guest]
	switch cmd.name {
	case "boot":
		return start(cmd.guest, cfg, cmd.build, true)
	case "stop":
		return stop(cmd.guest, definition.Type)
	case "delete":
		return deleteGuest(cmd.guest, definition.Type)
	case "rebuild":
		return rebuild(cmd, cfg)
	case "passwd":
		return passwd(cmd.guest, definition.Type, cmd.user)
	case "push-file":
		return pushFile(cmd, definition.Type)
	case "deliver-credentials":
		return deliverCredentials(cmd.guest, definition)
	}
	return fmt.Errorf("unknown command %s", cmd.name)
}
