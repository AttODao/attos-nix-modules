#!/usr/bin/env python3
"""Mock Incus transport; exercise the installer only in a temporary directory."""
import contextlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from unittest.mock import patch

import bootstrap

actual_run = subprocess.run
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    home = root / "home"
    home.mkdir()
    config = root / "config.json"
    config.write_text(json.dumps({"virtualMachines": ["worker"]}))
    source = root / "source.env"
    source.write_bytes(b"BOOTSTRAP_FIXTURE=fixture\n")
    source.chmod(0o600)
    shadow = root / "shadow"
    shadow.write_text("login:!:0:0:99999:7:::\n")
    state = {"type": "virtual-machine", "status": "Running", "password": "L", "uid": 1000}
    calls = []

    def transport(command, **kwargs):
        calls.append(command)
        if "query" in command:
            assert "--project" not in command and command[-1].endswith("?project=default")
            return subprocess.CompletedProcess(command, 0, json.dumps(state))
        assert "--env=PATH=/run/current-system/sw/bin:/bin" in command
        operation = command[command.index("--") + 1:]
        output = ""
        if operation[:2] == ["getent", "passwd"]:
            output = f"login:x:{state['uid']}:100::{home}:/bin/sh\n"
        elif operation[:2] == ["passwd", "--status"]:
            output = f"login {state['password']} 01/01/2026 0 99999 7 -1\n"
        elif operation[0] == "awk":
            return actual_run([*operation[:-1], str(shadow)], **kwargs)
        elif operation[0] == "/bin/sh":
            assert command[command.index("--user") + 1] == "1000"
            assert command[command.index("--group") + 1] == "100"
            assert "--mode=non-interactive" in command
            return actual_run(operation, **kwargs)
        elif operation[0] == "passwd":
            assert "--mode=interactive" in command
        else:
            assert "systemctl" in operation
        return subprocess.CompletedProcess(command, 0, output)

    def check(arguments, expected=0, terminal=True):
        calls.clear()
        with patch.object(sys, "argv", ["vm-bootstrap", "--config", str(config), "worker", *arguments]), \
             patch.object(subprocess, "run", transport), \
             patch.object(sys.stdin, "isatty", return_value=terminal), \
             contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            assert bootstrap.main() == expected, arguments

    check(["file", "login", str(source), "credentials/token.env", "--user-unit", "paseo-daemon.service"])
    destination = home / "credentials/token.env"
    assert destination.read_bytes() == source.read_bytes()
    assert destination.stat().st_mode & 0o777 == 0o600
    assert destination.parent.stat().st_mode & 0o777 == 0o700
    assert any("--user" in command and "systemctl" in command and "--user" in command[command.index("--") + 1:] for command in calls)
    source.write_bytes(b"REPLACEMENT_FIXTURE=fixture\n")
    check(["file", "login", str(source), "credentials/token.env", "--system-unit", "code-server.service"])
    assert destination.read_bytes() != source.read_bytes()
    assert not any("systemctl" in command for command in calls)
    check(["file", "login", str(source), "credentials/system.env", "--system-unit", "code-server.service"])
    assert any("systemctl" in command and "--user" not in command for command in calls)
    for path in ("/etc/token", "../token", "credentials/../token", "credentials//token", "credentials/./token"):
        check(["file", "login", str(source), path], 1)
    (home / "escape").symlink_to(root, target_is_directory=True)
    check(["file", "login", str(source), "escape/token.env"], 1)
    assert not (root / "token.env").exists()
    source.chmod(0o644)
    check(["file", "login", str(source), "credentials/public.env"], 1)
    source.chmod(0o600)
    linked = root / "linked.env"
    linked.symlink_to(source)
    check(["file", "login", str(linked), "credentials/link.env"], 1)
    fifo = root / "input.fifo"
    os.mkfifo(fifo, 0o600)
    check(["file", "login", str(fifo), "credentials/fifo.env"], 1)
    check(["passwd", "login"], 1, terminal=False)
    check(["passwd", "login"])
    assert any("--mode=interactive" in command for command in calls)
    state["password"] = "P"
    check(["passwd", "login"])
    assert not any("--mode=interactive" in command for command in calls)
    state["password"] = "L"
    shadow.write_text("login:!existing-fixture-hash:0:0:99999:7:::\n")
    check(["passwd", "login"], 1)
    assert not any("--mode=interactive" in command for command in calls)
    state["uid"] = 0
    check(["passwd", "login"], 1)
    state["uid"] = 1000
    for key, value in (("type", "container"), ("status", "Stopped")):
        previous = state[key]
        state[key] = value
        check(["passwd", "login"], 1)
        state[key] = previous
    assert not list(home.glob("**/.vm-bootstrap.*"))
print("PASS: scoped bootstrap, initial-only passwords, private user file installation and preservation")
