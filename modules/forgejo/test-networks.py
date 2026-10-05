#!/usr/bin/env python3
"""Check the three create-only app networks with a fake Docker CLI."""
import json
import os
from pathlib import Path
import shlex
import subprocess
import tempfile

modules = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    docker = root / "docker"
    docker.write_text('''#!/usr/bin/env python3
import json, os, pathlib, sys
log = pathlib.Path(os.environ["FAKE_LOG"])
calls = json.loads(log.read_text()) if log.exists() else []
calls.append(sys.argv[1:])
log.write_text(json.dumps(calls))
mode = os.environ["FAKE_MODE"]
if sys.argv[1:3] == ["network", "inspect"]:
    count = sum(call[1] == "inspect" for call in calls)
    sys.exit(0 if mode == "existing" or (mode == "race" and count == 2) else 1)
sys.exit(0 if mode == "fresh" else 1)
''')
    docker.chmod(0o755)
    for name in ("forgejo", "immich", "karakeep"):
        script = (modules / name / "ensure-network.sh").read_text()
        for placeholder, value in (("docker", str(docker)), ("network", name), ("subnet", "10.3.0.0/24"), ("gateway", "10.3.0.1")):
            script = script.replace("@" + placeholder + "@", shlex.quote(value))
        for mode in ("existing", "fresh", "race", "failed"):
            log = root / "calls.json"
            log.unlink(missing_ok=True)
            result = subprocess.run(["bash", "-eu", "-c", script], env={**os.environ, "FAKE_MODE": mode, "FAKE_LOG": str(log)}, capture_output=True)
            calls = json.loads(log.read_text())
            assert (result.returncode == 0) == (mode != "failed")
            assert calls[0] == ["network", "inspect", name]
            assert len(calls) == (1 if mode == "existing" else 2 if mode == "fresh" else 3)
            if name == "karakeep" and mode == "fresh":
                assert calls[1] == ["network", "create", "--driver", "bridge", "--subnet", "10.3.0.0/24", "--gateway", "10.3.0.1", "karakeep"]
print("app networks: OK")
