// Runtime-only key handling for WireGuard; metadata contains paths, not keys.
package main

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"net/netip"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
)

type client struct {
	Name             string  `json:"name"`
	Address          string  `json:"address"`
	IPv6Address      *string `json:"ipv6Address"`
	PrivateKeyFile   string  `json:"privateKeyFile"`
	PresharedKeyFile *string `json:"presharedKeyFile"`
}

type metadata struct {
	Clients                []client `json:"clients"`
	ClientDNS              string   `json:"clientDns"`
	ClientEndpoint         string   `json:"clientEndpoint"`
	ServerPublicKeyFile    string   `json:"serverPublicKeyFile"`
	ClientConfigsDirectory string   `json:"clientConfigsDirectory"`
	ClientConfigMode       string   `json:"clientConfigMode"`
}

var (
	clientName   = regexp.MustCompile(`^[a-z0-9][a-z0-9_-]*$`)
	endpointHost = regexp.MustCompile(`^[a-zA-Z0-9](?:[a-zA-Z0-9.-]*[a-zA-Z0-9])?$`)
)

func checkClients(entries []client) error {
	names, addresses := map[string]bool{}, map[string]bool{}
	for _, entry := range entries {
		if !clientName.MatchString(entry.Name) || names[entry.Name] {
			return errors.New("Invalid or duplicate WireGuard client name")
		}
		address, err := netip.ParseAddr(entry.Address)
		if err != nil || !address.Is4() || address.String() != entry.Address || addresses[entry.Address] {
			return errors.New("Invalid or duplicate WireGuard client address")
		}
		if entry.IPv6Address != nil {
			address, err := netip.ParseAddr(*entry.IPv6Address)
			if err != nil || !address.Is6() || address.Is4In6() || address.Zone() != "" ||
				address.String() != *entry.IPv6Address || addresses[*entry.IPv6Address] {
				return errors.New("Invalid or duplicate WireGuard client IPv6 address")
			}
			addresses[*entry.IPv6Address] = true
		}
		names[entry.Name] = true
		addresses[entry.Address] = true
	}
	return nil
}

func keyFile(path string) (string, error) {
	content, err := os.ReadFile(path)
	if err == nil {
		value := strings.TrimSpace(string(content))
		decoded, decodeErr := base64.StdEncoding.Strict().DecodeString(value)
		if decodeErr == nil && len(decoded) == 32 {
			return value, nil
		}
	}
	return "", fmt.Errorf("Cannot read a valid WireGuard key file: %s", path)
}

func checkEndpoint(value string) (string, error) {
	invalid := errors.New("Invalid WireGuard endpoint")
	index := strings.LastIndex(value, ":")
	if index < 0 {
		return "", invalid
	}
	host, port := value[:index], value[index+1:]
	number, err := strconv.Atoi(port)
	if port == "" || strings.Trim(port, "0123456789") != "" || err != nil || number < 1 || number > 65535 {
		return "", invalid
	}
	if strings.HasPrefix(host, "[") && strings.HasSuffix(host, "]") {
		address, err := netip.ParseAddr(host[1 : len(host)-1])
		if err != nil || !address.Is6() || address.Zone() != "" {
			return "", errors.New("Invalid WireGuard endpoint IPv6 address")
		}
	} else if !endpointHost.MatchString(host) {
		return "", errors.New("Invalid WireGuard endpoint hostname")
	}
	return value, nil
}

func render(meta metadata) (map[string]string, error) {
	if err := checkClients(meta.Clients); err != nil {
		return nil, err
	}
	dns, err := netip.ParseAddr(meta.ClientDNS)
	if err != nil || dns.Zone() != "" {
		return nil, errors.New("Invalid WireGuard client DNS address")
	}
	endpoint, err := checkEndpoint(meta.ClientEndpoint)
	if err != nil {
		return nil, err
	}
	serverKey, err := keyFile(meta.ServerPublicKeyFile)
	if err != nil {
		return nil, err
	}
	rendered := map[string]string{}
	// Read and validate every input before replacing any existing configuration.
	for _, entry := range meta.Clients {
		privateKey, err := keyFile(entry.PrivateKeyFile)
		if err != nil {
			return nil, err
		}
		preshared := ""
		if entry.PresharedKeyFile != nil && *entry.PresharedKeyFile != "" {
			key, err := keyFile(*entry.PresharedKeyFile)
			if err != nil {
				return nil, err
			}
			preshared = "\nPresharedKey = " + key
		}
		addresses, allowedIPs := entry.Address+"/32", "0.0.0.0/0"
		if entry.IPv6Address != nil {
			addresses += ", " + *entry.IPv6Address + "/128"
			allowedIPs += ", ::/0"
		}
		rendered[entry.Name] = "[Interface]\nPrivateKey = " + privateKey +
			"\nAddress = " + addresses + "\nDNS = " + dns.String() +
			"\n\n[Peer]\nPublicKey = " + serverKey + preshared +
			"\nAllowedIPs = " + allowedIPs + "\nEndpoint = " + endpoint +
			"\nPersistentKeepalive = 25\n"
	}
	return rendered, nil
}

func writeAtomic(root, name, text string, mode os.FileMode) error {
	handle, err := os.CreateTemp(root, "."+name+".")
	if err != nil {
		return err
	}
	temporary := handle.Name()
	defer os.Remove(temporary)
	_, err = handle.WriteString(text)
	if err == nil {
		err = handle.Chmod(mode)
	}
	if closeErr := handle.Close(); err == nil {
		err = closeErr
	}
	if err != nil {
		return err
	}
	return os.Rename(temporary, filepath.Join(root, name+".conf"))
}

func syncConfigs(meta metadata) error {
	if meta.ClientConfigMode == "" {
		meta.ClientConfigMode = "0600"
	}
	modes := map[string]os.FileMode{"0600": 0o600, "0640": 0o640, "0660": 0o660}
	mode, ok := modes[meta.ClientConfigMode]
	if !ok {
		return errors.New("Invalid client configuration file mode")
	}
	rendered, err := render(meta)
	if err != nil {
		return err
	}
	root := meta.ClientConfigsDirectory
	if !filepath.IsAbs(root) {
		return errors.New("Client configuration directory must be absolute")
	}
	if err := os.MkdirAll(root, 0o700); err != nil {
		return err
	}
	for _, entry := range meta.Clients {
		if err := writeAtomic(root, entry.Name, rendered[entry.Name], mode); err != nil {
			return err
		}
	}
	stale, err := filepath.Glob(filepath.Join(root, "*.conf"))
	if err != nil {
		return err
	}
	for _, path := range stale {
		base := filepath.Base(path)
		if _, keep := rendered[strings.TrimSuffix(base, ".conf")]; !keep && !strings.HasPrefix(base, ".") {
			if err := os.Remove(path); err != nil {
				return err
			}
		}
	}
	return nil
}

func qr(meta metadata, arguments []string) error {
	if err := checkClients(meta.Clients); err != nil {
		return err
	}
	if len(arguments) != 1 {
		return errors.New("Usage: wg-qr <client> | --list")
	}
	if arguments[0] == "--list" {
		for _, entry := range meta.Clients {
			fmt.Println(entry.Name)
		}
		return nil
	}
	known := false
	for _, entry := range meta.Clients {
		known = known || entry.Name == arguments[0]
	}
	if !known {
		return errors.New("Unknown WireGuard client; use wg-qr --list")
	}
	config, err := os.ReadFile(filepath.Join(meta.ClientConfigsDirectory, arguments[0]+".conf"))
	if err != nil {
		return err
	}
	var output bytes.Buffer
	command := exec.Command("qrencode", "-t", "ANSIUTF8")
	command.Stdin = bytes.NewReader(config)
	command.Stdout = &output
	if command.Run() != nil {
		return errors.New("qrencode operation failed")
	}
	_, err = os.Stdout.Write(output.Bytes())
	return err
}

func run(arguments []string) error {
	if len(arguments) < 2 {
		return errors.New("Usage: wireguard-runtime configs|qr METADATA [ARGS]")
	}
	content, err := os.ReadFile(arguments[1])
	if err != nil {
		return err
	}
	var meta metadata
	if err := json.Unmarshal(content, &meta); err != nil {
		return err
	}
	switch {
	case arguments[0] == "configs" && len(arguments) == 2:
		return syncConfigs(meta)
	case arguments[0] == "qr":
		return qr(meta, arguments[2:])
	}
	return errors.New("Unknown WireGuard runtime operation")
}

func main() {
	if err := run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, "WireGuard operation failed: "+err.Error())
		os.Exit(1)
	}
}
