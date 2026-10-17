#!/usr/bin/env python3
"""Create, start, stop, delete and rebuild declared local Incus KVM VMs."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time


ACTIONS = ("build", "dry-build", "dry-run", "dry-activate", "test", "switch", "boot", "list-generations")
APPLY = ("dry-activate", "test", "switch", "boot")
INCUS = ["incus", "--force-local"]
STORE_PATH = re.compile(r"/nix/store/[a-z0-9]{32}-[^/\s]+")
NAME = re.compile(r"[a-zA-Z0-9][a-zA-Z0-9-]{0,62}")
AGENT_TIMEOUT = 300


def run(command, capture=False, input=None):
    result = subprocess.run(command, check=True, text=True, input=input, stdout=subprocess.PIPE if capture else None)
    return result.stdout.strip() if capture else None


def incus(*arguments, capture=False, input=None):
    return run([*INCUS, "--project", "default", *arguments], capture=capture, input=input)


def guest(name, command, *, user=None, group=None, interactive=False):
    identity = [] if user is None else ["--user", str(user), "--group", str(group)]
    mode = "interactive" if interactive else "non-interactive"
    return [*INCUS, "--project", "default", "exec", name, *identity,
            "--env=PATH=/run/current-system/sw/bin:/bin", "--mode=" + mode, "--", *command]


def require_running(name):
    instance = json.loads(run([*INCUS, "query", "/1.0/instances/" + name + "?project=default"], capture=True))
    if instance.get("type") != "virtual-machine" or instance.get("status") != "Running":
        raise ValueError("Target must be an existing Running virtual-machine; start it with: vm " + name + " boot")


def instance(name):
    """Return the named instance, or None; never treat a container as the VM."""
    current = json.loads(incus("list", "--format=json", capture=True))
    if not isinstance(current, list) or not all(isinstance(item, dict) for item in current):
        raise ValueError("Unexpected Incus instance list")
    found = next((item for item in current if item.get("name") == name), None)
    if found is not None and found.get("type") != "virtual-machine":
        raise ValueError("Incus instance " + name + " is not a virtual-machine; it is never converted or deleted")
    return found


def flake(config, name, args):
    file = Path(config["flakeFile"]).resolve(strict=True)
    if file.name != "flake.nix" or not file.is_file():
        raise ValueError("flakeFile must name an existing flake.nix")
    nix_args = ["--no-write-lock-file", *(value for pair in args.override_input for value in ("--override-input", *pair))]
    configuration = "path:" + str(file.parent) + "#nixosConfigurations." + name + ".config"
    shape = json.loads(run(["nix", "eval", *nix_args, "--json", configuration,
                           "--apply", "c: { isContainer = c.boot.isContainer; incusAgent = c.virtualisation.incus.agent.enable; }"], capture=True))
    if shape != {"isContainer": False, "incusAgent": True}:
        raise ValueError("Selected flake configuration must be an Incus NixOS VM guest (not a container, with the Incus agent enabled)")
    command = ["nix", "build", *nix_args, "--print-out-paths"]
    for option, value in (("--max-jobs", args.max_jobs), ("--cores", args.cores)):
        if value is not None:
            command += [option, str(value)]
    return configuration, command


def image_file(value, metadata=False):
    path = Path(value)
    matches = sorted(path.rglob("tarball/*.tar.xz") if metadata else path.glob("*.qcow2"))
    if len(matches) != 1:
        raise ValueError("Expected exactly one Incus image archive under " + str(path))
    return matches[0]


def create(name, definition, config, args):
    configuration, command = flake(config, name, args)
    with tempfile.TemporaryDirectory(prefix="vm-image-") as directory:
        # Out-links keep the image outputs alive only until the import finishes.
        metadata, disk = (
            run([*command, "--out-link", str(Path(directory) / link), configuration + ".system.build." + attribute], capture=True)
            for link, attribute in (("metadata", "metadata"), ("disk", "qemuImage"))
        )
        source = (image_file(metadata, metadata=True), image_file(disk))
        # Incus split-image fingerprint is SHA-256(metadata archive || qcow2 bytes).
        digest = hashlib.sha256()
        for path in source:
            with open(path, "rb") as handle:
                for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                    digest.update(chunk)
        fingerprint = digest.hexdigest()
        images = json.loads(incus("image", "list", "--format=json", capture=True))
        existing = next((item for item in images if item.get("fingerprint") == fingerprint), None)
        if existing is None:
            incus("image", "import", *map(str, source))
        elif existing.get("type") != "virtual-machine":
            raise ValueError("Matching Incus image must have virtual-machine type")
    try:
        incus("launch", fingerprint, name, "--vm", "--quiet", input=json.dumps(definition["launchConfig"]))
    finally:
        # Existing VMs are updated by rebuild, never from the creation image.
        incus("image", "delete", fingerprint)


def sync_devices(name, definition):
    managed = definition["managedDeviceNames"]
    if not managed:
        return
    existing = incus("config", "device", "list", name, capture=True).splitlines()
    for device in managed:
        fields = definition["launchConfig"]["devices"][device]
        values = [key + "=" + (value if isinstance(value, str) else json.dumps(value)) for key, value in fields.items() if key != "type"]
        if device in existing:
            if values:
                incus("config", "device", "set", name, device, *values)
        else:
            incus("config", "device", "add", name, device, fields["type"], *values)


def start(name, config, args, *, create_missing=True):
    """Create a missing VM, upsert managed devices, start it and wait for the Incus agent."""
    definition = config["virtualMachines"][name]
    current = instance(name)
    if current is None:
        if not create_missing:
            raise ValueError("Virtual machine " + name + " does not exist; create it with: vm " + name + " boot")
        create(name, definition, config, args)
    elif current.get("status") not in ("Running", "Stopped"):
        raise RuntimeError("Refusing to change an Incus instance in state " + str(current.get("status")))
    sync_devices(name, definition)
    started = current is None or current["status"] == "Stopped"
    if current is not None and started:
        incus("start", name)
    deadline = time.monotonic() + AGENT_TIMEOUT
    while subprocess.run(guest(name, ["true"]), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode:
        if time.monotonic() > deadline:
            raise RuntimeError("Incus agent in " + name + " did not become ready")
        time.sleep(2)
    if started and definition["credentialUnit"] is not None:
        try:
            run(["systemctl", "restart", "--", definition["credentialUnit"]])
        except subprocess.CalledProcessError:
            raise RuntimeError("Credential delivery failed; run: systemctl restart " + definition["credentialUnit"])


def stop(name):
    current = instance(name)
    if current is None:
        raise ValueError("Virtual machine " + name + " does not exist")
    if current.get("status") == "Stopped":
        print(name + " is already stopped")
        return
    incus("stop", name)


def delete(name):
    current = instance(name)
    if current is None:
        print(name + " does not exist")
        return
    if current.get("status") != "Stopped":
        raise ValueError("Stop the virtual machine first: vm " + name + " stop")
    if not sys.stdin.isatty():
        raise ValueError("Deletion requires a terminal confirmation")
    if input("Type " + name + " to permanently delete the VM and its disks: ") != name:
        raise ValueError("Confirmation did not match; nothing was deleted")
    incus("delete", name)


def transfer(name, system):
    paths = run(["nix-store", "--query", "--requisites", system], capture=True).splitlines()
    if not paths or not all(STORE_PATH.fullmatch(path) for path in paths):
        raise ValueError("Invalid closure path list")
    # ponytail: one argv list; batch transport if closures approach the OS argument-size limit.
    missing = run(guest(name, ["nix-store", "--check-validity", "--print-invalid", *paths]), capture=True).splitlines()
    if not set(missing) <= set(paths):
        raise ValueError("Guest returned paths outside the built closure")
    if missing:
        with subprocess.Popen(["nix-store", "--export", *missing], stdout=subprocess.PIPE) as exporter:
            try:
                subprocess.run(guest(name, ["nix-store", "--import"]), stdin=exporter.stdout, check=True)
            finally:
                exporter.stdout.close()
            if exporter.wait():
                raise RuntimeError("Closure export failed; activation was not attempted")


def rebuild(name, config, args):
    if args.rollback and args.action not in APPLY:
        raise ValueError("--rollback requires dry-activate, test, switch or boot")
    native = ["/run/current-system/sw/bin/nixos-rebuild", args.action, "--no-reexec"]
    if args.action == "list-generations":
        require_running(name)
        run(guest(name, native))
        return
    if args.action in APPLY:
        start(name, config, args, create_missing=not args.rollback)
        if args.rollback:
            run(guest(name, [*native, "--rollback"]))
            return
    configuration, command = flake(config, name, args)
    installable = configuration + ".system.build.toplevel"
    if args.action in ("dry-build", "dry-run"):
        run([*command, "--no-link", "--dry-run", installable])
        return
    system = run([*command, "--no-link", installable], capture=True)
    if not STORE_PATH.fullmatch(system) or "-nixos-system-" not in system:
        raise ValueError("Build must return exactly one NixOS system store path")
    if args.action == "build":
        print(system)
        return
    transfer(name, system)
    # Native rebuild owns profile/generation semantics: test is temporary, boot does not activate.
    run(guest(name, [*native, "--store-path", system]))


def main():
    settings = argparse.ArgumentParser(add_help=False)
    settings.add_argument("--config", required=True)
    configured, arguments = settings.parse_known_args()
    with open(configured.config, encoding="utf-8") as handle:
        config = json.load(handle)
    names = config["virtualMachines"]
    if not isinstance(names, dict) or not all(NAME.fullmatch(name) for name in names):
        raise ValueError("Invalid declared virtual-machine map")
    building = argparse.ArgumentParser(add_help=False)
    building.add_argument("--max-jobs", type=int)
    building.add_argument("--cores", type=int)
    building.add_argument("--override-input", nargs=2, action="append", default=[], metavar=("NAME", "REFERENCE"))
    parser = argparse.ArgumentParser(prog="vm", description=__doc__)
    parser.add_argument("virtual_machine", choices=sorted(names))
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("boot", parents=[building], help="create the VM from the flake if missing, then start it")
    commands.add_parser("stop", help="shut the VM down")
    commands.add_parser("delete", help="delete a stopped VM and its disks after confirmation")
    rebuilding = commands.add_parser("rebuild", parents=[building], help="build and apply the guest system like nixos-rebuild")
    rebuilding.add_argument("action", nargs="?", default="switch", choices=ACTIONS)
    rebuilding.add_argument("--rollback", action="store_true", help="Use the guest's previous generation, without building")
    args = parser.parse_args(arguments)
    if any(getattr(args, option, None) is not None and getattr(args, option) < 0 for option in ("max_jobs", "cores")):
        parser.error("--max-jobs and --cores must be nonnegative")
    name = args.virtual_machine
    if args.command == "boot":
        start(name, config, args)
    elif args.command == "stop":
        stop(name)
    elif args.command == "delete":
        delete(name)
    else:
        rebuild(name, config, args)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.CalledProcessError) as error:
        print("vm: " + str(error), file=sys.stderr)
        sys.exit(1)
