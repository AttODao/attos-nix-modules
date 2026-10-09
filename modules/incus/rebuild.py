#!/usr/bin/env python3
"""Build locally and explicitly activate an existing local Incus KVM VM."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import sys


ACTIONS = ("build", "dry-build", "dry-run", "dry-activate", "test", "switch", "boot", "list-generations")
APPLY = ("dry-activate", "test", "switch", "boot")
INCUS = ["incus", "--force-local"]
STORE_PATH = re.compile(r"/nix/store/[a-z0-9]{32}-[^/\s]+")


def run(command, capture=False):
    result = subprocess.run(command, check=True, text=True, stdout=subprocess.PIPE if capture else None)
    return result.stdout.strip() if capture else None


def guest(name, command, *, user=None, group=None, interactive=False):
    identity = [] if user is None else ["--user", str(user), "--group", str(group)]
    mode = "interactive" if interactive else "non-interactive"
    return [*INCUS, "--project", "default", "exec", name, *identity,
            "--env=PATH=/run/current-system/sw/bin:/bin", "--mode=" + mode, "--", *command]


def require_running(name):
    instance = json.loads(run([*INCUS, "query", "/1.0/instances/" + name + "?project=default"], capture=True))
    if instance.get("type") != "virtual-machine" or instance.get("status") != "Running":
        raise ValueError("Target must be an existing Running virtual-machine; no instance will be created, converted, deleted or started")


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


def main():
    settings = argparse.ArgumentParser(add_help=False)
    settings.add_argument("--config", required=True)
    configured, arguments = settings.parse_known_args()
    with open(configured.config, encoding="utf-8") as handle:
        config = json.load(handle)
    names = config["virtualMachines"]
    if not isinstance(names, list) or not all(
        isinstance(name, str) and re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9-]{0,62}", name) for name in names
    ):
        raise ValueError("Invalid declared virtual-machine list")
    parser = argparse.ArgumentParser(prog="vm-rebuild", description=__doc__)
    parser.add_argument("action", choices=ACTIONS)
    parser.add_argument("virtual_machine", choices=names)
    parser.add_argument("--rollback", action="store_true", help="Use the guest's previous generation, without building")
    parser.add_argument("--max-jobs", type=int)
    parser.add_argument("--cores", type=int)
    parser.add_argument("--override-input", nargs=2, action="append", default=[], metavar=("NAME", "REFERENCE"))
    args = parser.parse_args(arguments)
    nix_args = [value for pair in args.override_input for value in ("--override-input", *pair)]
    if args.rollback and args.action not in APPLY:
        parser.error("--rollback requires dry-activate, test, switch or boot")
    if any(value is not None and value < 0 for value in (args.max_jobs, args.cores)):
        parser.error("--max-jobs and --cores must be nonnegative")

    if args.action in APPLY or args.action == "list-generations":
        require_running(args.virtual_machine)
        native = ["/run/current-system/sw/bin/nixos-rebuild", args.action, "--no-reexec"]
        if args.rollback or args.action == "list-generations":
            run(guest(args.virtual_machine, native + (["--rollback"] if args.rollback else [])))
            return

    file = Path(config["flakeFile"]).resolve(strict=True)
    if file.name != "flake.nix" or not file.is_file():
        raise ValueError("flakeFile must name an existing flake.nix")
    configuration = "path:" + str(file.parent) + "#nixosConfigurations." + args.virtual_machine + ".config"
    shape = json.loads(run(["nix", "eval", "--no-write-lock-file", *nix_args, "--json", configuration,
                           "--apply", "c: { isContainer = c.boot.isContainer; incusAgent = c.virtualisation.incus.agent.enable; }"], capture=True))
    if shape != {"isContainer": False, "incusAgent": True}:
        raise ValueError("Selected flake configuration must be an Incus NixOS VM guest (not a container, with the Incus agent enabled)")
    installable = configuration + ".system.build.toplevel"
    command = ["nix", "build", "--no-write-lock-file", *nix_args, "--no-link", "--print-out-paths"]
    for flag, value in (("--max-jobs", args.max_jobs), ("--cores", args.cores)):
        if value is not None:
            command += [flag, str(value)]
    if args.action in ("dry-build", "dry-run"):
        run([*command, "--dry-run", installable])
        return
    system = run([*command, installable], capture=True)
    if not STORE_PATH.fullmatch(system) or "-nixos-system-" not in system:
        raise ValueError("Build must return exactly one NixOS system store path")
    if args.action == "build":
        print(system)
        return
    transfer(args.virtual_machine, system)
    # Native rebuild owns profile/generation semantics: test is temporary, boot does not activate.
    run(guest(args.virtual_machine, [*native, "--store-path", system]))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.CalledProcessError) as error:
        print("vm-rebuild: " + str(error), file=sys.stderr)
        sys.exit(1)
