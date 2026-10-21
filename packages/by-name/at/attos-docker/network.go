package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"strings"
)

type options map[string]string

func (o options) String() string { return fmt.Sprint(map[string]string(o)) }

func (o options) Set(value string) error {
	key, val, ok := strings.Cut(value, "=")
	if !ok || key == "" {
		return errors.New("expected KEY=VALUE")
	}
	o[key] = val
	return nil
}

type bridgeSpec struct {
	name, subnet, gateway string
	options               options
}

type networkInfo struct {
	Driver     string
	Scope      string
	Attachable bool
	Options    map[string]string
	IPAM       struct {
		Config []map[string]any
	}
}

func networkEnsure(args []string) error {
	fs := flag.NewFlagSet("network ensure", flag.ContinueOnError)
	docker := fs.String("docker", "docker", "docker CLI path")
	spec := bridgeSpec{options: options{}}
	fs.StringVar(&spec.name, "name", "", "network name")
	fs.StringVar(&spec.subnet, "subnet", "", "IPv4/IPv6 subnet in CIDR form")
	fs.StringVar(&spec.gateway, "gateway", "", "gateway address (requires --subnet)")
	fs.Var(spec.options, "opt", "driver option KEY=VALUE (repeatable)")
	if err := fs.Parse(args); err != nil {
		return err
	}
	if spec.name == "" || fs.NArg() != 0 || (spec.gateway != "" && spec.subnet == "") {
		return errors.New("network ensure: --name is required; --gateway requires --subnet")
	}
	return ensureBridge(dockerCLI(*docker), spec)
}

// ensureBridge creates the bridge if missing, then verifies the actual network. A
// concurrent creator may win the race, so creation failure is followed by inspection.
func ensureBridge(d dockerCLI, spec bridgeSpec) error {
	raw, err := d.output("network", "inspect", spec.name)
	if err != nil {
		create := []string{"network", "create", "--driver", "bridge"}
		if spec.subnet != "" {
			create = append(create, "--subnet", spec.subnet)
		}
		if spec.gateway != "" {
			create = append(create, "--gateway", spec.gateway)
		}
		for key, value := range spec.options {
			create = append(create, "--opt", key+"="+value)
		}
		_, _ = d.output(append(create, spec.name)...)
		if raw, err = d.output("network", "inspect", spec.name); err != nil {
			return fmt.Errorf("could not create Docker network %s: %w", spec.name, err)
		}
	}
	return checkBridge(raw, spec)
}

// checkBridge never recreates a mismatching network: existing attachments and
// addresses belong to running services, so migration must stay explicit.
func checkBridge(raw string, spec bridgeSpec) error {
	var infos []networkInfo
	if err := json.Unmarshal([]byte(raw), &infos); err != nil || len(infos) != 1 {
		return fmt.Errorf("unexpected inspect output for Docker network %s", spec.name)
	}
	info := infos[0]
	mismatch := func(what string) error {
		return fmt.Errorf("existing Docker network %s has unexpected %s; migrate it explicitly", spec.name, what)
	}
	if info.Driver != "bridge" || info.Scope != "local" {
		return mismatch("driver or scope (want local bridge)")
	}
	for key, value := range spec.options {
		if info.Options[key] != value {
			return mismatch("option " + key)
		}
	}
	if spec.subnet != "" {
		want := map[string]any{"Subnet": spec.subnet}
		if spec.gateway != "" {
			want["Gateway"] = spec.gateway
		}
		if len(info.IPAM.Config) != 1 || !sameConfig(info.IPAM.Config[0], want) {
			return mismatch("IPAM configuration")
		}
	}
	return nil
}

func sameConfig(got, want map[string]any) bool {
	for key, value := range got {
		if s, ok := value.(string); ok && s == "" {
			continue
		}
		if m, ok := value.(map[string]any); ok && len(m) == 0 {
			continue
		}
		if want[key] != value {
			return false
		}
	}
	for key, value := range want {
		if got[key] != value {
			return false
		}
	}
	return true
}
