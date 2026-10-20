package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"maps"
	"os"
	"regexp"
	"slices"
)

var guestName = regexp.MustCompile(`^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$`)

const (
	virtualMachine = "virtual-machine"
	container      = "container"
)

type credentialFile struct {
	Source string `json:"source"`
	Owner  string `json:"owner"`
	Group  string `json:"group"`
	Mode   string `json:"mode"`
}

type guestDefinition struct {
	Type                   string                    `json:"type"`
	LaunchConfig           json.RawMessage           `json:"launchConfig"`
	ManagedDeviceNames     []string                  `json:"managedDeviceNames"`
	CredentialUnit         *string                   `json:"credentialUnit"`
	CredentialFiles        map[string]credentialFile `json:"credentialFiles"`
	CredentialRestartUnits []string                  `json:"credentialRestartUnits"`
}

type config struct {
	Flake  string                     `json:"flake"`
	Guests map[string]guestDefinition `json:"guests"`
}

func (c *config) names() []string {
	return slices.Sorted(maps.Keys(c.Guests))
}

func loadConfig(path string) (*config, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	return parseConfig(data)
}

func parseConfig(data []byte) (*config, error) {
	var cfg config
	if err := json.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("invalid configuration: %w", err)
	}
	if cfg.Guests == nil {
		return nil, errors.New("invalid declared guest map")
	}
	for name, definition := range cfg.Guests {
		if !guestName.MatchString(name) || (definition.Type != virtualMachine && definition.Type != container) {
			return nil, errors.New("invalid declared guest map")
		}
		for destination, file := range definition.CredentialFiles {
			if !file.valid() {
				return nil, errors.New("invalid credential file " + destination)
			}
		}
	}
	return &cfg, nil
}

var (
	accountName = regexp.MustCompile(`^[a-z_][a-z0-9_-]*\$?$`)
	fileMode    = regexp.MustCompile(`^0[0-7]{3}$`)
)

// valid mirrors the module's typed option so the guest shell only ever sees safe words.
func (f credentialFile) valid() bool {
	return f.Source != "" && accountName.MatchString(f.Owner) && accountName.MatchString(f.Group) && fileMode.MatchString(f.Mode)
}

// devices returns launchConfig.devices; managed device names must be present.
func (d guestDefinition) devices() (map[string]map[string]json.RawMessage, error) {
	var launch struct {
		Devices map[string]map[string]json.RawMessage `json:"devices"`
	}
	if err := json.Unmarshal(d.LaunchConfig, &launch); err != nil {
		return nil, fmt.Errorf("invalid launchConfig: %w", err)
	}
	return launch.Devices, nil
}
