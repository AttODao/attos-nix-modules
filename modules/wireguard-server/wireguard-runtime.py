#!/usr/bin/env python3
"""Runtime-only key handling for WireGuard; metadata contains paths, not keys."""
import base64
import ipaddress
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


def clients(metadata):
    entries = metadata["clients"]
    names, addresses = set(), set()
    if not isinstance(entries, list):
        raise ValueError("WireGuard clients must be a list")
    for entry in entries:
        name, address = entry["name"], entry["address"]
        if not re.fullmatch(r"[a-z0-9][a-z0-9_-]*", name) or name in names:
            raise ValueError("Invalid or duplicate WireGuard client name")
        if str(ipaddress.IPv4Address(address)) != address or address in addresses:
            raise ValueError("Invalid or duplicate WireGuard client address")
        names.add(name)
        addresses.add(address)
    return entries


def key_file(path):
    try:
        value = Path(path).read_text(encoding="ascii").strip()
        if len(base64.b64decode(value, validate=True)) != 32:
            raise ValueError()
    except (OSError, UnicodeError, ValueError) as error:
        raise ValueError("Cannot read a valid WireGuard key file: " + str(path)) from error
    return value


def checked_endpoint(value):
    host, separator, port = value.rpartition(":")
    if not separator or not port.isdecimal() or not 1 <= int(port) <= 65535:
        raise ValueError("Invalid WireGuard endpoint")
    if host.startswith("[") and host.endswith("]"):
        ipaddress.IPv6Address(host[1:-1])
    elif not re.fullmatch(r"[a-zA-Z0-9](?:[a-zA-Z0-9.-]*[a-zA-Z0-9])?", host):
        raise ValueError("Invalid WireGuard endpoint hostname")
    return value


def run(command, **kwargs):
    result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs)
    if result.returncode:
        raise RuntimeError(command[0] + " operation failed")
    return result.stdout


def sync_peers(metadata):
    entries = clients(metadata)
    interface = metadata["interface"]
    if not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9_-]{0,14}", interface):
        raise ValueError("Invalid WireGuard interface")
    text = "[Interface]\nPrivateKey = " + key_file(metadata["privateKeyFile"]) + "\n"
    port = metadata.get("listenPort")
    if port is not None:
        if type(port) is not int or not 1 <= port <= 65535:
            raise ValueError("Invalid WireGuard listen port")
        text += "ListenPort = " + str(port) + "\n"
    for entry in entries:
        text += "\n[Peer]\nPublicKey = " + key_file(entry["publicKeyFile"]) + "\nAllowedIPs = " + entry["address"] + "/32\n"
    namespace = metadata.get("namespace")
    prefix = []
    if namespace and namespace != "init":
        if not re.fullmatch(r"[a-zA-Z0-9_.-]+", namespace):
            raise ValueError("Invalid WireGuard network namespace")
        prefix = ["ip", "netns", "exec", namespace]
    path = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="ascii", prefix=interface + ".", dir=os.environ.get("RUNTIME_DIRECTORY"), delete=False) as handle:
            path = Path(handle.name)
            handle.write(text)
        run(prefix + ["wg", "syncconf", interface, str(path)])
    finally:
        if path is not None:
            path.unlink(missing_ok=True)


def sync_configs(metadata):
    mode = metadata.get("clientConfigMode", "0600")
    if mode not in ("0600", "0640", "0660"):
        raise ValueError("Invalid client configuration file mode")
    entries = clients(metadata)
    dns = str(ipaddress.ip_address(metadata["clientDns"]))
    endpoint = checked_endpoint(metadata["clientEndpoint"])
    server_key = key_file(metadata["serverPublicKeyFile"])
    rendered = {}
    # Read and validate every input before replacing any existing configuration.
    for entry in entries:
        rendered[entry["name"]] = (
            "[Interface]\nPrivateKey = " + key_file(entry["privateKeyFile"])
            + "\nAddress = " + entry["address"] + "/32\nDNS = " + dns
            + "\n\n[Peer]\nPublicKey = " + server_key
            + "\nAllowedIPs = 0.0.0.0/0\nEndpoint = " + endpoint
            + "\nPersistentKeepalive = 25\n"
        )
    root = Path(metadata["clientConfigsDirectory"])
    if not root.is_absolute():
        raise ValueError("Client configuration directory must be absolute")
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    for name, text in rendered.items():
        temporary = None
        try:
            with tempfile.NamedTemporaryFile(mode="w", encoding="ascii", prefix="." + name + ".", dir=root, delete=False) as handle:
                temporary = Path(handle.name)
                handle.write(text)
                os.fchmod(handle.fileno(), int(mode, 8))
            os.replace(temporary, root / (name + ".conf"))
        finally:
            if temporary is not None:
                temporary.unlink(missing_ok=True)
    for path in root.glob("*.conf"):
        if path.stem not in rendered:
            path.unlink()


def qr(metadata, arguments):
    names = [entry["name"] for entry in clients(metadata)]
    if len(arguments) != 1:
        raise ValueError("Usage: wg-qr <client> | --list")
    if arguments[0] == "--list":
        sys.stdout.write("".join(name + "\n" for name in names))
        return
    if arguments[0] not in names:
        raise ValueError("Unknown WireGuard client; use wg-qr --list")
    path = Path(metadata["clientConfigsDirectory"]) / (arguments[0] + ".conf")
    output = run(["qrencode", "-t", "ANSIUTF8"], input=path.read_bytes())
    sys.stdout.buffer.write(output)


def main():
    operation, metadata_file, *arguments = sys.argv[1:]
    with open(metadata_file, encoding="utf-8") as handle:
        metadata = json.load(handle)
    if operation == "peers" and not arguments:
        sync_peers(metadata)
    elif operation == "configs" and not arguments:
        sync_configs(metadata)
    elif operation == "qr":
        qr(metadata, arguments)
    else:
        raise ValueError("Unknown WireGuard runtime operation")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print("WireGuard operation failed: " + str(error), file=sys.stderr)
        sys.exit(1)
