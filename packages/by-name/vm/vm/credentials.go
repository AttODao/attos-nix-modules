package main

import (
	"errors"
	"maps"
	"path"
	"slices"
)

// The guest parent must be a dedicated root:root 0700 directory; it is never chmod/chowned.
const ensureParent = `PATH=/run/current-system/sw/bin:/bin
[ ! -L "$1" ]
mkdir -p -m 0700 -- "$1"
[ "$(stat -c %u:%g:%a -- "$1")" = "0:0:700" ]
`

// deliverCredentials places each declared credential as root:root 0600 via a
// temporary file and rename. Host activation never starts VMs; vm boot
// restarts the delivery unit after starting one.
func deliverCredentials(name string, definition vmDefinition) error {
	current, err := instance(name)
	if err != nil {
		return err
	}
	if current == nil || current["status"] == "Stopped" {
		return nil
	}
	for _, destination := range slices.Sorted(maps.Keys(definition.CredentialFiles)) {
		if !path.IsAbs(destination) || path.Clean(destination) != destination {
			return errors.New("invalid credential destination " + destination)
		}
		steps := [][]string{
			guest(name, []string{"/bin/sh", "-eu", "-c", ensureParent, "sh", path.Dir(destination)}, nil, false),
			incusArgv("file", "push", "--uid", "0", "--gid", "0", "--mode", "0600",
				definition.CredentialFiles[destination], name+destination+".new"),
			guest(name, []string{"mv", "-fT", "--", destination + ".new", destination}, nil, false),
		}
		for _, step := range steps {
			if _, err := run(step, false, nil); err != nil {
				return err
			}
		}
	}
	if len(definition.CredentialRestartUnits) > 0 {
		_, err := run(guest(name, append([]string{"systemctl", "restart"}, definition.CredentialRestartUnits...), nil, false), false, nil)
		return err
	}
	return nil
}
