#!/usr/bin/env python3
"""Run the actual bridge script against fake Docker; never contact a daemon."""
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile

source = Path(__file__).with_name("ensure-network.sh").read_text()
with tempfile.TemporaryDirectory(prefix="karakeep network '") as temporary:
    root = Path(temporary)
    docker = root / "fake-docker"
    log = root / "calls.jsonl"
    docker.write_text(f"#!{sys.executable}\n" + '''import json, os, sys
from pathlib import Path
log = Path(os.environ["CALL_LOG"])
calls = log.read_text().splitlines() if log.exists() else []
with log.open("a") as output:
    output.write(json.dumps(sys.argv[1:]) + "\\n")
mode = os.environ["MODE"]
if sys.argv[2] == "inspect":
    sys.exit(0 if mode == "existing" or (mode == "race" and calls) else 1)
sys.exit(0 if mode == "missing" else 1)
''')
    docker.chmod(0o755)
    script = source.replace("@docker@", shlex.quote(str(docker)))
    script = script.replace("@subnet@", shlex.quote("10.10.0.0/24"))
    script = script.replace("@gateway@", shlex.quote("10.10.0.1"))
    inspect = ["network", "inspect", "karakeep"]
    create = ["network", "create", "--driver", "bridge", "--subnet",
              "10.10.0.0/24", "--gateway", "10.10.0.1", "karakeep"]
    for mode, expected, success in [
        ("existing", [inspect], True),
        ("missing", [inspect, create], True),
        ("race", [inspect, create, inspect], True),
        ("failure", [inspect, create, inspect], False),
    ]:
        log.unlink(missing_ok=True)
        result = subprocess.run(["bash", "-e", "-c", script],
                                env={**os.environ, "MODE": mode, "CALL_LOG": str(log)},
                                capture_output=True, text=True)
        assert (result.returncode == 0) == success, (mode, result.stderr)
        assert [json.loads(line) for line in log.read_text().splitlines()] == expected, mode
print("karakeep network: existing, create, concurrent create and failure passed")
