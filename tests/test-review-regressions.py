#!/usr/bin/env python3
"""Mock-only regression checks; usage: python3 tests/test-review-regressions.py NIXPKGS HM."""
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile

repo = Path(__file__).resolve().parents[1]
nixpkgs, home_manager = map(Path, sys.argv[1:])
with tempfile.TemporaryDirectory(prefix="attos-review-") as directory:
    root = Path(directory)
    data = root / "Open ' % Terminal"
    expression = '''
      { nixpkgs, homeManager, root, uid, gid }:
      let
        t = import ./tests/lib.nix { inherit nixpkgs homeManager; };
        c = t.cfgFor [{
          modules.pipeasio.enable = true;
          modules.hyprland.enable = true;
          modules.noctalia.screenRecorder.enable = true;
          home-manager.users.test.xdg.userDirs = {
            pictures = "${root}/Pictures";
            videos = "${root}/Videos";
          };
          modules.open-terminal = {
            enable = true;
            dataDir = root;
            environmentFile = "/run/secrets/terminal.env";
            inherit uid gid;
          };
          virtualisation.oci-containers.containers.open-terminal.environment.OPEN_TERMINAL_CORS_ALLOWED_ORIGINS = "http://localhost:8080";
        }];
        h = t.hm c "test";
      in
      assert t.lib.elem "open-terminal-prepare.service" c.systemd.services.docker-open-terminal.requires;
      assert t.lib.elem "open-terminal-prepare.service" c.systemd.services.docker-open-terminal.after;
      assert c.systemd.services.open-terminal-prepare.unitConfig.RequiresMountsFor == [root];
      assert !(t.lib.any (rule: t.lib.hasInfix root rule) c.systemd.tmpfiles.rules);
      {
        activations = map (name: h.home.activation.${name}.data) [
          "registerPipeasioSteamPrefixes"
          "ensureHyprlandScreenshotsDir"
          "ensureNoctaliaRecordingsDir"
        ];
        prepare = c.systemd.services.open-terminal-prepare.script;
      }
    '''
    result = subprocess.run([
        "nix-instantiate", "--eval", "--strict", "--json", "--expr", expression,
        "--arg", "nixpkgs", str(nixpkgs), "--arg", "homeManager", str(home_manager),
        "--argstr", "root", str(data), "--arg", "uid", str(os.getuid()),
        "--arg", "gid", str(os.getgid()),
    ], cwd=repo, check=True, capture_output=True, text=True)
    scripts = json.loads(result.stdout)
    marker = root / "prefix.dll"
    marker.write_text("old driver")
    register = root / "register"
    register.write_text("#!/bin/sh\nprintf 'new driver' > " + shlex.quote(str(marker)) + "\n")
    register.chmod(0o700)
    activation = "\n".join(scripts["activations"])
    activation = re.sub(r"/nix/store/[^\s]+/bin/pipeasio-register-steam-prefixes", shlex.quote(str(register)), activation)
    activation = re.sub(r"/nix/store/[^\s]+/bin/install", shlex.quote(shutil.which("install")), activation)
    command = "set -eu\nsource " + shlex.quote(str(home_manager / "lib/bash/home-manager.sh")) + "\n" + activation
    subprocess.run(["bash", "-c", command], env={**os.environ, "DRY_RUN": "1"}, check=True, capture_output=True)
    assert marker.read_text() == "old driver"
    assert not data.exists(), "dry-run created directories"
    env = os.environ.copy()
    env.pop("DRY_RUN", None)
    subprocess.run(["bash", "-c", command], env=env, check=True, capture_output=True)
    assert marker.read_text() == "new driver"
    assert (data / "Pictures/Screenshots").is_dir()
    assert (data / "Videos/Recordings").is_dir()

    # Mock only chown, allowing unprivileged tests to exercise actual install/mode/path handling.
    installs = root / "installs.jsonl"
    install = root / "install"
    install.write_text(f"#!{sys.executable}\n" +
        "import json, subprocess, sys\n" +
        f"with open({str(installs)!r}, 'a') as log: log.write(json.dumps(sys.argv[1:]) + '\\n')\n" +
        f"subprocess.run([{shutil.which('install')!r}, *sys.argv[1:4], sys.argv[-1]], check=True)\n")
    install.chmod(0o700)
    prepare = re.sub(r"/nix/store/[^\s]+/bin/install", shlex.quote(str(install)), scripts["prepare"])
    subprocess.run(["bash", "-c", prepare], env=env, check=True, capture_output=True)
    commands = [json.loads(line) for line in installs.read_text().splitlines()]
    assert commands == [
        ["-d", "-m", "0700", "-o", "root", "-g", "root", str(data)],
        ["-d", "-m", "0700", "-o", str(os.getuid()), "-g", str(os.getgid()), str(data / "workspace")],
    ]
    assert data.stat().st_mode & 0o777 == 0o700
    assert (data / "workspace").stat().st_mode & 0o777 == 0o700
print("activation dry-run/live and Open Terminal preparation: passed")
