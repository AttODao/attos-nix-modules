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

var vmName = regexp.MustCompile(`^[a-zA-Z0-9][a-zA-Z0-9-]{0,62}$`)

type vmDefinition struct {
	LaunchConfig           json.RawMessage   `json:"launchConfig"`
	ManagedDeviceNames     []string          `json:"managedDeviceNames"`
	CredentialUnit         *string           `json:"credentialUnit"`
	CredentialFiles        map[string]string `json:"credentialFiles"`
	CredentialRestartUnits []string          `json:"credentialRestartUnits"`
}

type config struct {
	FlakeFile       string                  `json:"flakeFile"`
	VirtualMachines map[string]vmDefinition `json:"virtualMachines"`
}

func (c *config) names() []string {
	return slices.Sorted(maps.Keys(c.VirtualMachines))
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
	if cfg.VirtualMachines == nil {
		return nil, errors.New("invalid declared virtual-machine map")
	}
	for name := range cfg.VirtualMachines {
		if !vmName.MatchString(name) {
			return nil, errors.New("invalid declared virtual-machine map")
		}
	}
	return &cfg, nil
}

// devices returns launchConfig.devices; managed device names must be present.
func (d vmDefinition) devices() (map[string]map[string]json.RawMessage, error) {
	var launch struct {
		Devices map[string]map[string]json.RawMessage `json:"devices"`
	}
	if err := json.Unmarshal(d.LaunchConfig, &launch); err != nil {
		return nil, fmt.Errorf("invalid launchConfig: %w", err)
	}
	return launch.Devices, nil
}
