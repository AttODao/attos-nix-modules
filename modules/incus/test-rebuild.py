#!/usr/bin/env python3
"""Rootless CLI/transport sandbox; no real Nix store, Incus or profiles are touched."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

SYSTEM = "/nix/store/" + "a" * 32 + "-nixos-system-desktop-test"
DEPENDENCY = "/nix/store/" + "b" * 32 + "-dependency"
SCRIPT = Path(__file__).with_name("rebuild.py")
MOCK = r'''
import json, os, sys
from pathlib import Path
name = Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ["LOG"], "a") as log:
    log.write(json.dumps([name, *args]) + "\n")
system = os.environ["SYSTEM"]
if name == "nix":
    if args[0] == "eval": print("false" if os.environ.get("NOT_CONTAINER") else "true")
    elif os.environ.get("FAIL_BUILD"): sys.exit(1)
    elif "--dry-run" not in args: print(system)
elif name == "nix-store":
    if "--query" in args:
        print(system); print(os.environ["DEPENDENCY"])
    elif "--export" in args:
        sys.stdout.buffer.write(b"sandbox-nar")
        if os.environ.get("FAIL_EXPORT"): sys.exit(1)
    else: sys.exit(90)
elif name == "incus":
    assert args[0] == "--force-local"
    if "query" in args:
        assert "--project" not in args and args[-1].endswith("?project=default")
        print(json.dumps({"type": "container", "status": os.environ.get("STATE", "Running")}))
    elif "--check-validity" in args:
        assert args[:3] == ["--force-local", "--project", "default"]
        if not os.environ.get("NO_MISSING"): print(system)
    elif "--import" in args:
        assert sys.stdin.buffer.read() == b"sandbox-nar"
        if os.environ.get("FAIL_IMPORT"): sys.exit(1)
    elif "/run/current-system/sw/bin/nixos-rebuild" in args:
        pass
    else: sys.exit(91)
else: sys.exit(92)
'''


def check():
    with tempfile.TemporaryDirectory(prefix="container-rebuild-") as temporary:
        root = Path(temporary)
        tools = root / "bin"
        tools.mkdir()
        for name in ("nix", "nix-store", "incus"):
            tool = tools / name
            tool.write_text("#!" + sys.executable + "\n" + MOCK)
            tool.chmod(0o700)
        flake = root / "checkout with spaces" / "flake.nix"
        flake.parent.mkdir()
        flake.write_text("{}")
        config = root / "config.json"
        config.write_text(json.dumps({"flakeFile": str(flake), "containers": ["desktop", "development"]}))
        log = root / "commands.jsonl"

        def invoke(action, name="desktop", flags=(), **changes):
            log.write_text("")
            env = dict(os.environ, PATH=str(tools), LOG=str(log), SYSTEM=SYSTEM, DEPENDENCY=DEPENDENCY, **changes)
            result = subprocess.run([sys.executable, str(SCRIPT), "--config", str(config), action, name, *flags],
                                    env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            return result, [json.loads(line) for line in log.read_text().splitlines()]

        result, commands = invoke("build", flags=("--max-jobs", "2", "--cores", "2"))
        assert result.returncode == 0 and result.stdout.strip() == SYSTEM
        assert len(commands) == 2 and all(command[0] == "nix" for command in commands)
        assert commands[1][-1] == str(flake.parent) + "#nixosConfigurations.desktop.config.system.build.toplevel"
        assert "--no-write-lock-file" in commands[1] and "--no-link" in commands[1]
        for action in ("dry-build", "dry-run"):
            result, commands = invoke(action)
            assert result.returncode == 0 and len(commands) == 2 and "--dry-run" in commands[1]
        for action in ("dry-activate", "test", "switch", "boot"):
            result, commands = invoke(action)
            assert result.returncode == 0, result.stderr
            assert any("--import" in command for command in commands[:-1])
            assert commands[-1][-4:] == [action, "--no-reexec", "--store-path", SYSTEM]
            assert not any(command[0] == "nix-env" for command in commands)
        result, commands = invoke("switch", NO_MISSING="1")
        assert result.returncode == 0 and not any("--import" in command for command in commands)
        for failure in ("FAIL_BUILD", "FAIL_IMPORT", "FAIL_EXPORT"):
            result, commands = invoke("switch", **{failure: "1"})
            assert result.returncode != 0
            assert not any("/run/current-system/sw/bin/nixos-rebuild" in command for command in commands)
        result, commands = invoke("switch", STATE="Stopped")
        assert result.returncode != 0 and len(commands) == 1
        result, commands = invoke("switch", NOT_CONTAINER="1")
        assert result.returncode != 0 and len(commands) == 2
        for action, name in (("switch", "attofort"), ("switch", "desktop;bad"), ("delete", "desktop")):
            result, commands = invoke(action, name)
            assert result.returncode != 0 and not commands
        flake.unlink()
        for action, flags in (("switch", ("--rollback",)), ("list-generations", ())):
            result, commands = invoke(action, flags=flags)
            assert result.returncode == 0 and len(commands) == 2
            assert commands[-1][-1] == ("--rollback" if flags else "--no-reexec")
    print("container rebuild: OK")


if __name__ == "__main__":
    check()
