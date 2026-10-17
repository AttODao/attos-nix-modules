#!/usr/bin/env python3
"""Check the standalone-release install script with tiny assets and mocked tools."""
import os
from pathlib import Path
import subprocess
import tempfile

here = Path(__file__).resolve().parent
with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    source = root / "release"
    browser = source / "src/browser/media"
    workbench = source / "lib/vscode/out/vs/code/browser/workbench/workbench.html"
    (source / "bin").mkdir(parents=True)
    browser.mkdir(parents=True)
    workbench.parent.mkdir(parents=True)
    executable = source / "bin/code-server"
    executable.write_text("#!/bin/sh\nexit 0\n")
    executable.chmod(0o755)
    font = root / "JetBrainsMonoNerdFontMono-Regular.ttf"
    font.write_bytes(b"mock font")
    tools = root / "tools"
    tools.mkdir()
    compressor = tools / "woff2_compress"
    compressor.write_text("#!/usr/bin/env python3\nfrom pathlib import Path\nimport sys\nPath(sys.argv[1]).with_suffix('.woff2').write_bytes(b'compressed font')\n")
    compressor.chmod(0o755)
    replacement = root / "replace.py"
    replacement.write_text("""from pathlib import Path
import sys
path, flag, old, new = sys.argv[1:]
assert flag == '--replace-fail'
p = Path(path)
s = p.read_text()
assert old in s, 'expected upstream stylesheet link is missing'
p.write_text(s.replace(old, new))
""")
    shell = """set -eu
runHook() { :; }
substituteInPlace() { python3 "$REPLACE_HELPER" "$@"; }
source "$INSTALL_SCRIPT"
"""
    original = '<link rel="stylesheet" href="{{WORKBENCH_WEB_BASE_URL}}/out/vs/code/browser/workbench/workbench.css">\n'
    workbench.write_text(original)
    env = {**os.environ, "CODE_SERVER_SOURCE": str(source), "NERD_FONT_FILE": str(font),
           "NERD_FONT_CSS": str(here / "nerd-font.css"), "INSTALL_SCRIPT": str(here / "install.sh"),
           "REPLACE_HELPER": str(replacement), "PATH": f"{tools}:{os.environ['PATH']}"}
    out = root / "result"
    result = subprocess.run(["bash", "-c", shell], env={**env, "out": str(out)}, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    assert (out / "bin/code-server").is_symlink()
    installed = out / "libexec/code-server"
    assert (installed / "src/browser/media/JetBrainsMonoNerdFontMono-Regular.woff2").is_file()
    assert not (installed / "src/browser/media/JetBrainsMonoNerdFontMono-Regular.ttf").exists()
    assert "nerd-font.css" in (installed / "lib/vscode/out/vs/code/browser/workbench/workbench.html").read_text()
    assert workbench.read_text() == original
    workbench.write_text("upstream layout changed\n")
    result = subprocess.run(["bash", "-c", shell], env={**env, "out": str(root / "bad-result")}, capture_output=True, text=True)
    assert result.returncode != 0
print("code-server install: OK")
