#!/usr/bin/env python3
"""Mock-only regression check; run directly, without ffmpeg or a recorder."""
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import time


SOURCE = Path(__file__).resolve().parent


def executable(path, body):
    path.write_text(body)
    path.chmod(0o755)
    return path


def wait_for(predicate):
    deadline = time.monotonic() + 5
    while not predicate():
        assert time.monotonic() < deadline, "background conversion timed out"
        time.sleep(0.01)


def main():
    with tempfile.TemporaryDirectory(prefix="recording-test-") as directory:
        root = Path(directory)
        recordings = root / "recordings with ' spaces"
        recordings.mkdir()
        calls = root / "ffmpeg-args.json"
        recorder_args = root / "recorder-args.json"
        env = dict(os.environ, PATH=f"{root}:{os.environ['PATH']}",
                   TMPDIR=str(root), CALLS=str(calls), RECORDER_ARGS=str(recorder_args),
                   FFMPEG_STATUS="0", RECORDER_STATUS="0", FFMPEG_GATE="")
        executable(root / "ffmpeg", f"#!{sys.executable}\n" + '''import json, os, sys, time
from pathlib import Path
Path(os.environ["CALLS"]).write_text(json.dumps(sys.argv[1:]))
gate = os.environ["FFMPEG_GATE"]
if gate:
    deadline = time.monotonic() + 5
    while not Path(gate).exists():
        if time.monotonic() >= deadline:
            sys.exit(99)
        time.sleep(0.01)
Path(sys.argv[-1]).write_text("converted" if os.environ["FFMPEG_STATUS"] == "0" else "partial")
sys.exit(int(os.environ["FFMPEG_STATUS"]))
''')
        recorder = executable(root / "mock recorder", f"#!{sys.executable}\n" + '''import json, os, sys
from pathlib import Path
Path(os.environ["RECORDER_ARGS"]).write_text(json.dumps(sys.argv[1:]))
Path(os.environ["RECORDER_OUTPUT"]).write_text("original")
sys.exit(int(os.environ["RECORDER_STATUS"]))
''')

        def render(name, replacements):
            body = (SOURCE / name).read_text()
            for key, value in replacements.items():
                body = body.replace(f"@{key}@", shlex.quote(str(value)))
            return executable(root / name, "#!/usr/bin/env bash\n" + body)

        converter = render("recording-to-x.sh", {"RECORDINGS_DIRECTORY": recordings})
        wrapper = render("gpu-screen-recorder-auto-x.sh", {
            "RECORDINGS_DIRECTORY": recordings, "GPU_SCREEN_RECORDER": recorder,
            "RECORDING_TO_X": converter})

        def run(script, *args):
            return subprocess.run(["bash", str(script), *map(str, args)], env=env,
                                  capture_output=True, text=True, timeout=5)

        assert run(converter).returncode == 1
        assert run(converter, recordings / "missing.mp4").returncode == 1
        assert not calls.exists()

        old, newest, excluded = (recordings / name for name in
                                 ("old.mp4", "new ' recording.mp4", "latest-x.mp4"))
        for stamp, path in enumerate((old, newest, excluded), 1):
            path.write_text("original")
            os.utime(path, (stamp, stamp))
        result = run(converter)
        assert result.returncode == 0, result.stderr
        output = newest.with_name(newest.stem + "-x.mp4")
        assert output.read_text() == "converted"
        assert all(path.read_text() == "original" for path in (old, newest, excluded))
        args = json.loads(calls.read_text())
        tone_map = (
            "zscale=transfer=linear,format=gbrpf32le,tonemap=tonemap=mobius:desat=0,"
            "sidedata=mode=delete,zscale=transfer=bt709:matrix=bt709:primaries=bt709:range=tv,"
            "scale=1280:720:force_original_aspect_ratio=decrease:flags=lanczos,"
            "pad=1280:720:(ow-iw)/2:(oh-ih)/2:color=black,setsar=1,format=yuv420p")
        assert args[:-1] == ["-hide_banner", "-y", "-i", str(newest)] + shlex.split(
            "-map 0:v:0 -map 0:a:0? -map_metadata 0 -map_chapters 0 -vf") + [tone_map] + shlex.split(
            "-c:v libx264 -preset slow -crf 18 -profile:v high -pix_fmt yuv420p "
            "-color_primaries bt709 -color_trc bt709 -colorspace bt709 "
            "-c:a aac -b:a 160k -ar 48000 -ac 2 -movflags +faststart -f mp4")
        assert Path(args[-1]).parent == output.parent and Path(args[-1]) != output
        assert not Path(args[-1]).exists()

        # A partial ffmpeg write must neither replace existing data nor survive cleanup.
        safe_output = root / "nested output" / "safe.mp4"
        safe_output.parent.mkdir()
        safe_output.write_text("keep me")
        env["FFMPEG_STATUS"] = "23"
        assert run(converter, newest, safe_output).returncode == 23
        assert safe_output.read_text() == "keep me" and newest.read_text() == "original"
        assert list(safe_output.parent.iterdir()) == [safe_output]
        absent_output = safe_output.parent / "absent.mp4"
        assert run(converter, newest, absent_output).returncode == 23
        assert list(safe_output.parent.iterdir()) == [safe_output]
        env["FFMPEG_STATUS"] = "0"

        # A gate proves the wrapper returns before conversion, without a timing race.
        for index, flag in enumerate(("-o", "--output", "-o=", "--output=")):
            source = root / f"explicit ' output {index}.mp4"
            converted = source.with_name(source.stem + "-x.mp4")
            log = source.with_name(source.stem + "-x.log")
            gate = root / f"gate-{index}"
            env.update(RECORDER_OUTPUT=str(source), FFMPEG_GATE=str(gate))
            calls.unlink()
            options = [flag + str(source)] if flag.endswith("=") else [flag, str(source)]
            result = run(wrapper, "--other-option", *options)
            assert result.returncode == 0, result.stderr
            assert json.loads(recorder_args.read_text()) == ["--other-option", *options]
            wait_for(calls.exists)
            assert json.loads(calls.read_text())[3] == str(source)
            assert not converted.exists()
            gate.touch()
            wait_for(lambda: log.exists() and f"Wrote {converted}\n" in log.read_text())
            assert converted.read_text() == "converted" and source.read_text() == "original"

        calls.unlink()
        failed = root / "failed recording.mp4"
        env.update(RECORDER_OUTPUT=str(failed), RECORDER_STATUS="17", FFMPEG_GATE="")
        result = run(wrapper, "--output", failed)
        assert result.returncode == 17
        assert failed.read_text() == "original"
        # Log creation is synchronous with launch, so absence needs no arbitrary sleep.
        assert not failed.with_name(failed.stem + "-x.log").exists()
        assert not failed.with_name(failed.stem + "-x.mp4").exists()
        assert not calls.exists()
    print("recording regression test: OK")


if __name__ == "__main__":
    main()
