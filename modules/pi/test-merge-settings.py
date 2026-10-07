#!/usr/bin/env python3
"""Evaluate and exercise the shared HM activation in temporary directories only.

python3 modules/pi/test-merge-settings.py /path/to/nixpkgs /path/to/home-manager
"""
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def main():
    nixpkgs, home_manager = sys.argv[1:]
    expression = '''{ nixpkgs, homeManager }:
      let
        t = import ./tests/lib.nix {
          inherit nixpkgs homeManager;
          nixpkgsConfig.allowUnfree = true;
        };
        h = t.hmFor [{
          modules.pi = { enable = true; settingsMode = "merge"; };
          home-manager.users.test.programs.pi-coding-agent = {
            configDir = "/home/test/custom-pi";
            settings = {
              defaultProvider = "shared-provider";
              defaultModel = "shared-model";
              providers.example = { model = "shared"; extra = true; };
            };
          };
        }];
      in {
        dir = h.programs.pi-coding-agent.configDir;
        defaults = h.programs.pi-coding-agent.settings;
        script = h.home.activation.mergePiSettings.data;
      }
    '''
    evaluated = subprocess.check_output([
        "nix-instantiate", "--eval", "--strict", "--json", "--read-write-mode",
        "--expr", expression, "--arg", "nixpkgs", nixpkgs,
        "--arg", "homeManager", home_manager,
    ], cwd=ROOT)
    pi = json.loads(evaluated)
    with tempfile.TemporaryDirectory(prefix="pi-settings-test-") as directory:
        sandbox = Path(directory)
        defaults = sandbox / "defaults.json"
        defaults.write_text(json.dumps(pi["defaults"]))
        agent = sandbox / "agent"
        script = pi["script"].replace(shlex.quote(pi["dir"]), shlex.quote(str(agent)))
        script, count = re.subn(r"/nix/store/[a-z0-9]{32}-pi-settings\.json", str(defaults), script)
        assert count == 1 and pi["dir"] not in script

        def run(dry=False):
            # HM's run helper must skip writes on dry-run, too.
            return subprocess.run([
                "bash", "-c", 'run() { if [ -z "$DRY_RUN_CMD" ]; then "$@"; fi; }\n' + script,
            ], env={**os.environ, "DRY_RUN_CMD": "echo" if dry else ""}, capture_output=True)

        assert run(dry=True).returncode == 0 and not agent.exists()
        assert run().returncode == 0
        settings = agent / "settings.json"

        def check_file():
            assert not settings.is_symlink()
            assert settings.stat().st_uid == os.getuid()
            assert settings.stat().st_mode & 0o777 == 0o600
            assert not list(agent.glob(".settings.*"))

        check_file()
        assert json.loads(settings.read_text()) == pi["defaults"]
        manual = {
            "defaultProvider": "manual-provider", "defaultModel": "manual-model",
            "providers": {"example": {"model": "manual", "manual": True}},
            "sessions": {"other": True, "autoTitle": {"refreshTurns": 9}},
        }
        settings.write_text(json.dumps(manual))
        before = settings.read_bytes()
        assert run(dry=True).returncode == 0 and settings.read_bytes() == before
        assert run().returncode == 0
        merged = json.loads(settings.read_text())
        assert merged["defaultProvider"] == "manual-provider"
        assert merged["defaultModel"] == "manual-model"
        assert merged["providers"]["example"] == {"model": "manual", "manual": True, "extra": True}
        assert merged["sessions"] == {"other": True, "autoTitle": {"refreshTurns": 9}}
        assert merged["defaultTools"] == pi["defaults"]["defaultTools"]
        check_file()
        for invalid in ["invalid JSON", "[]", "null", "42", '"string"', "", "{} {}"]:
            settings.write_text(invalid)
            assert run().returncode != 0
            assert settings.read_text() == invalid
            check_file()

        # A legacy declarative symlink becomes writable, without changing its source.
        settings.unlink()
        legacy = sandbox / "legacy-settings.json"
        legacy.write_text(json.dumps(manual))
        legacy.chmod(0o444)
        settings.symlink_to(legacy)
        assert run(dry=True).returncode == 0 and settings.is_symlink()
        assert run().returncode == 0 and json.loads(legacy.read_text()) == manual
        assert json.loads(settings.read_text())["defaultModel"] == "manual-model"
        check_file()
        settings.unlink()
        legacy.chmod(0o600)
        legacy.write_text("invalid JSON")
        settings.symlink_to(legacy)
        assert run().returncode != 0 and settings.is_symlink()
        assert legacy.read_text() == "invalid JSON"
        assert not list(agent.glob(".settings.*"))
    print("Shared Pi settings merge: OK (sandbox only)")


if __name__ == "__main__":
    main()
