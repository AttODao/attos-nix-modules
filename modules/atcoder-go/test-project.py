#!/usr/bin/env python3
"""Exercise the bundled project scaffold with a fake Go; no network or cookies."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

assets = Path(__file__).resolve().parent / "assets"
with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    bundle = root / "bundle"
    bundle.mkdir()
    shutil.copytree(assets / "atcoder", bundle / ".atcoder")
    for src, dest in [("devenv.nix", "devenv.nix"), ("devenv.yaml", "devenv.yaml"),
                      ("envrc", ".envrc"), ("gitignore", ".gitignore")]:
        shutil.copyfile(assets / src, bundle / dest)
    tools = root / "bin"
    tools.mkdir()
    go = tools / "go"
    go.write_text('#!/usr/bin/env bash\nprintf "%s\\n" "$*" >> "$GO_LOG"\n'
                  'if [ "$1 $2" = "mod init" ]; then printf "module %s\\n" "$3" > go.mod; fi\n')
    go.chmod(0o755)
    log = root / "go.log"
    env = {**os.environ, "ATCODER_PROJECT_ASSETS": str(bundle),
           "ATCODER_GO_BIN_DIR": str(tools), "GO_LOG": str(log)}
    project = root / "project with spaces"
    project.mkdir()

    def run(command, cwd=project):
        return subprocess.run(["bash", "-euo", "pipefail", str(assets / "atcoder/scripts/project"), command],
                              cwd=cwd, env=env, text=True, capture_output=True)

    for _ in range(2):
        result = run("init")
        assert result.returncode == 0, result.stderr
    assert log.read_text().count("mod init atcoder.jp/golang") == 1
    assert "mod edit -go=1.25.1" in log.read_text()
    assert "github.com/monkukui/ac-library-go" in log.read_text()
    assert (project / ".atcoder/template/main.go").read_bytes() == (assets / "atcoder/template/main.go").read_bytes()
    assert (project / ".atcoder/snippet/main.go").read_bytes() == (assets / "atcoder/snippet/main.go").read_bytes()
    assert (project / ".envrc").read_bytes() == (assets / "envrc").read_bytes()
    assert len((project / ".gitignore").read_text().splitlines()) == 4
    (project / ".envrc").write_text("keep my environment\n")
    (project / ".atcoder/template/main.go").write_text("keep my template\n")
    assert run("init").returncode == 0
    assert (project / ".envrc").read_text() == "keep my environment\n"
    assert (project / ".atcoder/template/main.go").read_text() == "keep my template\n"
    child = project / "contest"
    child.mkdir()
    assert run("sync", child).returncode == 0
    assert run("bogus").returncode == 2
    empty = root / "empty"
    empty.mkdir()
    assert run("sync", empty).returncode != 0
print("bundled AtCoder Go project: OK")
