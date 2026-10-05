#!/usr/bin/env python3
import os
from pathlib import Path
import subprocess
import tempfile

script = Path(__file__).with_name("stage-config.sh")
with tempfile.TemporaryDirectory(prefix="ytdl stage ") as directory:
    root = Path(directory)
    data = root / "media"
    config = data / "config"
    config.mkdir(parents=True)
    (data / "history.json").write_text("keep media history")
    (config / "extra.yaml").write_text("consumer config")
    (config / "config-twitch.yaml").write_text("obsolete")
    environment = {**os.environ, "YTDL_SUB_DATA_DIR": str(data), "YTDL_SUB_UID": str(os.getuid()), "YTDL_SUB_GID": str(os.getgid())}
    for key in ("CONFIG", "YOUTUBE", "TWITCH", "CRON", "COOKIE"):
        source = root / key
        source.write_text(key)
        variable = "YTDL_SUB_COOKIE_FILE" if key == "COOKIE" else "YTDL_SUB_" + key + "_FILE"
        environment[variable] = str(source)
    subprocess.run(["bash", str(script)], env=environment, check=True, capture_output=True)
    assert (config / "config.yaml").read_text() == "CONFIG"
    assert (config / "subscriptions-youtube.yaml").read_text() == "YOUTUBE"
    assert (config / "cron").stat().st_mode & 0o777 == 0o755
    assert not (config / "config-twitch.yaml").exists()
    assert (data / "history.json").read_text() == "keep media history"
    assert (config / "extra.yaml").read_text() == "consumer config"
    assert not (config / "cookies.txt").exists()
    before = {path.name: path.read_bytes() for path in config.iterdir()}
    Path(environment["YTDL_SUB_TWITCH_FILE"]).unlink()
    result = subprocess.run(["bash", str(script)], env=environment, capture_output=True)
    assert result.returncode != 0
    assert {path.name: path.read_bytes() for path in config.iterdir()} == before
print("ytdl staging: OK")
