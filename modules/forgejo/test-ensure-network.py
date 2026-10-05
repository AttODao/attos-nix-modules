#!/usr/bin/env python3
"""Run the network asset against fake Docker; no daemon or network is used."""
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile


FAKE_DOCKER = """\
import json, os, sys
from pathlib import Path
state = Path(os.environ["STATE"])
with open(os.environ["LOG"], "a") as log:
    log.write(json.dumps(sys.argv[1:]) + "\\n")
assert sys.argv[1:3] in (["network", "inspect"], ["network", "create"])
if sys.argv[2] == "inspect":
    success = state.exists()
else:
    success = os.environ["MODE"] == "missing"
    if os.environ["MODE"] in ("missing", "race"):
        state.touch()
if not success:
    print("fake Docker failure", file=sys.stderr)
sys.exit(0 if success else 1)
"""


def main():
    template = Path(__file__).with_name("ensure-network.sh").read_text()
    network = "forgejo 'quoted' $(false)"
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        docker = root / "fake docker's"
        docker.write_text(f"#!{sys.executable}\n" + FAKE_DOCKER)
        docker.chmod(0o755)
        script = template.replace("@docker@", shlex.quote(str(docker))).replace(
            "@network@", shlex.quote(network)
        )
        for mode, operations in (
            ("existing", ["inspect"]),
            ("missing", ["inspect", "create"]),
            ("race", ["inspect", "create", "inspect"]),
            ("failure", ["inspect", "create", "inspect"]),
        ):
            state, log = root / f"{mode}.state", root / f"{mode}.log"
            if mode == "existing":
                state.touch()
            result = subprocess.run(
                ["bash", "-e", "-c", script],
                env={**os.environ, "MODE": mode, "STATE": str(state), "LOG": str(log)},
                capture_output=True,
                text=True,
                check=False,
            )
            calls = [json.loads(line) for line in log.read_text().splitlines()]
            assert calls == [["network", operation, network] for operation in operations], calls
            assert (result.returncode == 0) == (mode != "failure"), result
            assert result.stdout == "", result
            assert (result.stderr != "") == (mode == "failure"), result
    print("Forgejo network: existing, missing, race, and failure passed")


if __name__ == "__main__":
    main()
