#!/usr/bin/env python3
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from unittest.mock import patch
from urllib.parse import unquote

script = Path(__file__).with_name("provision.py")
spec = importlib.util.spec_from_file_location("provision", script)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    metadata, rootfs = root / "metadata.tar.xz", root / "rootfs.squashfs"
    metadata.write_bytes(b"fake metadata")
    rootfs.write_bytes(b"fake rootfs")
    definition = {
        "alias": "consumer-image", "metadata": str(metadata), "rootfs": str(rootfs),
        "launchConfig": {"profiles": ["consumer"], "devices": {"proxy": {"type": "proxy", "listen": "tcp:127.0.0.1:4444", "connect": "tcp:127.0.0.1:8080"}}},
        "managedDeviceNames": ["proxy"],
    }
    manifest = {"containers": {"kept": definition, "new": definition}}
    aliases = {"consumer-image": {"name": "consumer-image", "target": "old-image", "description": "keep"}}
    instances = {"kept": {"name": "kept", "status": "Running"}}
    calls = []
    fail_import = False

    def fake_incus(*arguments, input=None):
        calls.append((arguments, input))
        if arguments[:2] == ("storage", "list"):
            return json.dumps([{"name": "consumer-pool"}])
        if arguments[0] == "list":
            return json.dumps(list(instances.values()))
        if arguments[:3] == ("image", "alias", "list"):
            return json.dumps(list(aliases.values()))
        if arguments[:2] == ("image", "import"):
            if fail_import:
                raise RuntimeError("fake import failure")
            name = arguments[-1]
            aliases[name] = {"name": name, "target": "new-image"}
        elif arguments[:3] == ("image", "alias", "rename"):
            entry = aliases.pop(arguments[3])
            entry["name"] = arguments[4]
            aliases[arguments[4]] = entry
        elif arguments[:3] == ("image", "alias", "delete"):
            aliases.pop(arguments[3])
        elif arguments[0] == "query":
            name = unquote(arguments[1].rsplit("/", 1)[1])
            aliases[name].update(json.loads(arguments[-1]))
        elif arguments[0] == "launch":
            instances[arguments[2]] = {"name": arguments[2], "status": "Running"}
            assert json.loads(input) == definition["launchConfig"]
        elif arguments[:3] == ("config", "device", "list"):
            return "proxy\nunmanaged\n"
        elif arguments[:3] == ("config", "device", "set"):
            assert arguments[4] == "proxy" and all(not field.startswith("type=") for field in arguments[5:])
        elif arguments[0] == "start":
            instances[arguments[1]]["status"] = "Running"
        else:
            raise AssertionError(arguments)
        return ""

    with patch.object(module, "incus", fake_incus):
        assert module.condition("consumer-pool") == 1 and module.condition("missing") == 0
        stamps = root / "stamps"
        module.provision(manifest, str(stamps))
        assert aliases["consumer-image"]["target"] == "new-image" and aliases["consumer-image"]["description"] == "keep"
        assert [args[2] for args, _ in calls if args[0] == "launch"] == ["new"]
        assert not any(args[0] in ("delete", "stop") for args, _ in calls)
        calls.clear()
        instances["kept"]["status"] = "Stopped"
        module.provision(manifest, str(stamps))
        assert ("start", "kept") in [args for args, _ in calls]
        assert not any(args[0] == "launch" or args[:2] == ("image", "import") for args, _ in calls)
        # Removed declarations are not guest deletion requests.
        calls.clear()
        module.provision({"containers": {}}, str(stamps))
        assert set(instances) == {"kept", "new"}
        # Unexpected guest state is rejected before image/device mutation.
        instances["kept"]["status"] = "Frozen"
        calls.clear()
        try:
            module.provision(manifest, str(stamps))
        except RuntimeError:
            pass
        else:
            raise AssertionError("Frozen guest was changed")
        assert [args[0] for args, _ in calls] == ["list"]
        instances["kept"]["status"] = "Running"
        stamp = stamps / "image-consumer-image.source"
        old_stamp = stamp.read_bytes()
        newer = root / "new-rootfs.squashfs"
        newer.write_bytes(b"new source")
        fail_import = True
        changed = {"containers": {"kept": {**definition, "rootfs": str(newer)}}}
        try:
            module.provision(changed, str(stamps))
        except RuntimeError:
            pass
        else:
            raise AssertionError("Import failure was ignored")
        assert stamp.read_bytes() == old_stamp and aliases["consumer-image"]["target"] == "new-image"

    # Verify the actual ExecCondition CLI error status, not a skip/success code.
    executable = root / "incus"
    executable.write_text("#!/bin/sh\nprintf 'not-json\\n'\n")
    executable.chmod(0o755)
    result = subprocess.run([sys.executable, str(script), "condition", "consumer-pool"], env={**os.environ, "PATH": str(root) + os.pathsep + os.environ["PATH"]}, capture_output=True)
    assert result.returncode == 255
print("incus provisioning: OK")
