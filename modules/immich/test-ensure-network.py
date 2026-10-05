# Run with: python3 modules/immich/test-ensure-network.py
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile

source = Path(__file__).with_name("ensure-network.sh").read_text()
fake = """import json
import os
from pathlib import Path
import sys

state = Path(os.environ["FAKE_STATE"])
args = sys.argv[1:]
with (state / "calls").open("a") as log:
    log.write(json.dumps(args) + "\\n")
assert args[:1] == ["network"] and args[2:] == ["immich"], args
present = state / "present"
if args[1] == "inspect":
    sys.exit(0 if present.exists() else 1)
assert args[1] == "create", args
mode = os.environ["FAKE_MODE"]
if mode != "failure":
    present.touch()
sys.exit(1 if mode in ["race", "failure"] else 0)
"""
inspect = ["network", "inspect", "immich"]
create = ["network", "create", "immich"]
for mode in ["existing", "missing", "race", "failure"]:
    with tempfile.TemporaryDirectory(dir=Path(__file__).parent) as directory:
        state = Path(directory)
        docker = state / "fake docker's tool"
        docker.write_text(f"#!{sys.executable}\n" + fake)
        docker.chmod(0o755)
        script = state / "ensure.sh"
        script.write_text(source.replace("@docker@", shlex.quote(str(docker.resolve()))))
        if mode == "existing":
            (state / "present").touch()
        env = {**os.environ, "FAKE_STATE": str(state.resolve()), "FAKE_MODE": mode}

        def run():
            return subprocess.run(["sh", "-eu", str(script)], env=env,
                                  capture_output=True, text=True)

        def calls():
            return [json.loads(line) for line in (state / "calls").read_text().splitlines()]

        result = run()
        assert (result.returncode == 0) == (mode != "failure"), (mode, result)
        expected = [inspect] if mode == "existing" else [inspect, create]
        if mode in ["race", "failure"]:
            expected += [inspect]
        assert calls() == expected, (mode, calls())
        if mode != "failure":
            # Idempotent while present, then recreate after a prune.
            assert run().returncode == 0
            assert calls() == expected + [inspect]
            (state / "present").unlink()
            assert run().returncode == 0
            pruned = [inspect, create] + ([inspect] if mode == "race" else [])
            assert calls() == expected + [inspect] + pruned
print("Immich network: existing/missing/race/failure and prune recheck OK")
