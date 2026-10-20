package main

import (
	"errors"
	"os/exec"
	"strings"
	"testing"
)

func TestCheckBridge(t *testing.T) {
	traefik := bridgeSpec{name: "native", subnet: "172.30.0.0/24", gateway: "172.30.0.1",
		options: options{"com.docker.network.bridge.name": "br-native"}}
	plain := bridgeSpec{name: "forgejo", options: options{}}
	cases := []struct {
		name string
		spec bridgeSpec
		raw  string
		ok   bool
	}{
		{"exact", traefik, `[{"Driver":"bridge","Scope":"local","Options":{"com.docker.network.bridge.name":"br-native"},"IPAM":{"Config":[{"Subnet":"172.30.0.0/24","Gateway":"172.30.0.1"}]}}]`, true},
		{"empty extras ignored", traefik, `[{"Driver":"bridge","Scope":"local","Options":{"com.docker.network.bridge.name":"br-native"},"IPAM":{"Config":[{"Subnet":"172.30.0.0/24","Gateway":"172.30.0.1","IPRange":"","AuxiliaryAddresses":{}}]}}]`, true},
		{"wrong gateway", traefik, `[{"Driver":"bridge","Scope":"local","Options":{"com.docker.network.bridge.name":"br-native"},"IPAM":{"Config":[{"Subnet":"172.30.0.0/24","Gateway":"172.30.0.254"}]}}]`, false},
		{"extra range", traefik, `[{"Driver":"bridge","Scope":"local","Options":{"com.docker.network.bridge.name":"br-native"},"IPAM":{"Config":[{"Subnet":"172.30.0.0/24","Gateway":"172.30.0.1","IPRange":"172.30.0.0/25"}]}}]`, false},
		{"two configs", traefik, `[{"Driver":"bridge","Scope":"local","Options":{"com.docker.network.bridge.name":"br-native"},"IPAM":{"Config":[{"Subnet":"172.30.0.0/24","Gateway":"172.30.0.1"},{"Subnet":"fd00::/64"}]}}]`, false},
		{"missing option", traefik, `[{"Driver":"bridge","Scope":"local","Options":{},"IPAM":{"Config":[{"Subnet":"172.30.0.0/24","Gateway":"172.30.0.1"}]}}]`, false},
		{"plain auto subnet", plain, `[{"Driver":"bridge","Scope":"local","Options":{},"IPAM":{"Config":[{"Subnet":"172.18.0.0/16","Gateway":"172.18.0.1"}]}}]`, true},
		{"overlay rejected", plain, `[{"Driver":"overlay","Scope":"swarm","IPAM":{"Config":[]}}]`, false},
		{"not one network", plain, `[]`, false},
	}
	for _, c := range cases {
		err := checkBridge(c.raw, c.spec)
		if (err == nil) != c.ok {
			t.Errorf("%s: got %v, want ok=%v", c.name, err, c.ok)
		}
	}
}

func TestOptionsFlag(t *testing.T) {
	o := options{}
	if err := o.Set("a=b=c"); err != nil || o["a"] != "b=c" {
		t.Fatalf("got %v %v", o, err)
	}
	if err := o.Set("novalue"); err == nil || !strings.Contains(err.Error(), "KEY=VALUE") {
		t.Fatal("expected KEY=VALUE error")
	}
}

func TestCommandError(t *testing.T) {
	exit := &exec.ExitError{Stderr: []byte("Error response from daemon: network x not found\n")}
	got := commandError([]string{"network", "inspect", "x"}, exit).Error()
	if got != "docker network inspect failed: Error response from daemon: network x not found" {
		t.Fatalf("got %q", got)
	}
	plain := errors.New("executable file not found")
	if got := commandError([]string{"network", "inspect", "x"}, plain).Error(); !strings.HasSuffix(got, ": executable file not found") {
		t.Fatalf("got %q", got)
	}
}
