package main

import (
	"errors"
	"maps"
	"path"
	"slices"
)

// The guest parent must be a dedicated 0700 directory owned by the credential's
// owner and group ($2:$3); it is created so when missing and never chmod/chowned.
const ensureParent = `PATH=/run/current-system/sw/bin:/bin
[ ! -L "$1" ]
if [ ! -e "$1" ]; then
  mkdir -p -m 0700 -- "$1"
  chown -- "$2:$3" "$1"
fi
[ "$(stat -c %U:%G:%a -- "$1")" = "$2:$3:700" ]
`

// The pushed file arrives root:root 0600; hand it to the owner before the atomic rename.
const installFile = `PATH=/run/current-system/sw/bin:/bin
chown -- "$2:$3" "$1.new"
chmod -- "$4" "$1.new"
mv -fT -- "$1.new" "$1"
`

// deliverCredentials places each declared credential with its owner, group and
// mode via a temporary file and rename. Host activation never starts guests;
// guest boot restarts the delivery unit after starting one.
func deliverCredentials(name string, definition guestDefinition) error {
	current, err := instance(name, definition.Type)
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
		file := definition.CredentialFiles[destination]
		if !file.valid() {
			return errors.New("invalid credential file " + destination)
		}
		steps := [][]string{
			guest(name, []string{"/bin/sh", "-eu", "-c", ensureParent, "sh", path.Dir(destination), file.Owner, file.Group}, nil, false),
			incusArgv("file", "push", "--uid", "0", "--gid", "0", "--mode", "0600",
				file.Source, name+destination+".new"),
			guest(name, []string{"/bin/sh", "-eu", "-c", installFile, "sh", destination, file.Owner, file.Group, file.Mode}, nil, false),
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
