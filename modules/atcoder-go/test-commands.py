#!/usr/bin/env python3
"""Build only tiny mock tools; never fetch Go modules or access real cookies."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

package = Path(__file__).resolve().parents[2] / "packages/atcoder-commands.nix"
with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    home = root / "home with '$dollar"
    source = os.environ.get("NIXPKGS")
    nixpkgs = f"(builtins.toPath {json.dumps(source)})" if source else "<nixpkgs>"
    expression = r'''
      let
        pkgs = import NIXPKGS {};
        go = pkgs.writeShellScriptBin "go" ''
          printf '%s\n' "$*" >> "$GO_LOG"
          if [ "$1 $2" = "mod init" ]; then
            printf 'module %s\n' "$3" > go.mod
          fi
          if [ "$1" = "version" ]; then echo 'go version go1.25'; fi
        '';
        aclogin = pkgs.writeShellScriptBin "aclogin" ''printf '%s\n' "$*"'';
      in pkgs.callPackage (builtins.toPath PACKAGE) {
        inherit go aclogin;
        homeDirectory = HOME_DIRECTORY;
      }
    '''.replace("NIXPKGS", nixpkgs).replace("PACKAGE", json.dumps(str(package))).replace("HOME_DIRECTORY", json.dumps(str(home)))
    built = subprocess.run(
        ["nix-build", "--no-out-link", "--expr", expression],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    assert built.returncode == 0, built.stderr
    bin_dir = Path(built.stdout.strip().splitlines()[-1]) / "bin"
    log = root / "go.log"
    env = {**os.environ, "GO_LOG": str(log), "PATH": f"{bin_dir}:{os.environ['PATH']}"}

    def run(*args, cwd=root):
        return subprocess.run([str(bin_dir / args[0]), *args[1:]], cwd=cwd, env=env,
                              text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    bad = run("atcoder-go", "bogus")
    assert bad.returncode == 2 and "usage:" in bad.stderr
    (root / "devenv.nix").write_text("{}\n")
    (root / ".envrc").write_text("keep me\n")
    (root / ".gitignore").write_text("old\n")
    for _ in range(2):
        result = run("atcoder-go", "init")
        assert result.returncode == 0, result.stderr
    assert (root / ".envrc").read_text() == "keep me\n"
    assert (root / ".gitignore").read_text().splitlines() == ["old", ".direnv/", ".devenv/"]
    assert log.read_text().count("mod init atcoder.jp/golang") == 1
    assert "get " not in log.read_text() and "mod download" not in log.read_text()
    original = (root / "go.mod").read_text()
    child = root / "contest"
    child.mkdir()
    result = run("atcoder-sync", cwd=child)
    assert result.returncode == 0, result.stderr
    assert "mod download" in log.read_text()
    assert (root / "go.mod").read_text() == original
    result = run("go-run", "argument with spaces")
    assert result.returncode == 0, result.stderr
    assert "run . argument with spaces" in log.read_text()
    login = run("acc-login", "--browser", "none")
    assert login.returncode == 0, login.stderr
    assert (home / ".local/share/online-judge-tools").is_dir()
    assert (home / ".config/atcoder-cli-nodejs").is_dir()
    assert "--tools oj acc" in login.stdout
    assert str(home) in login.stdout
    assert not (home / ".local/share/online-judge-tools/cookie.jar").exists()
print("atcoder commands: OK")
