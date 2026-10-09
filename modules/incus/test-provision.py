#!/usr/bin/env python3
import hashlib
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

# Even a root CLI configured for another remote/project cannot redirect operations.
with patch.object(module.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, stdout="ok")) as cli:
    module.incus("list", "--format=json")
    assert cli.call_args.args[0] == ["incus", "--force-local", "--project", "default", "list", "--format=json"]
    module.incus("query", "/1.0/images/aliases/consumer-image?project=default", "-X", "PUT", "-d", "{}")
    assert cli.call_args.args[0] == ["incus", "--force-local", "query", "/1.0/images/aliases/consumer-image?project=default", "-X", "PUT", "-d", "{}"]

with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    metadata, disk = root / "metadata.tar.xz", root / "disk.qcow2"
    metadata.write_bytes(b"fake metadata")
    disk.write_bytes(b"fake disk")
    definition = {
        "alias": "consumer-image", "metadata": str(metadata), "disk": str(disk),
        "launchConfig": {"profiles": ["consumer"], "devices": {"proxy": {"type": "proxy", "listen": "tcp:127.0.0.1:4444", "connect": "tcp:127.0.0.1:8080"}}},
        "managedDeviceNames": ["proxy"],
    }
    manifest = {"virtualMachines": {"kept": definition, "new": definition}}
    fingerprint = hashlib.sha256(metadata.read_bytes() + disk.read_bytes()).hexdigest()
    images = {"old-image": {"fingerprint": "old-image", "type": "container"}}
    aliases = {"consumer-image": {"name": "consumer-image", "target": "old-image", "type": "container", "description": "keep"}}
    instances = {"kept": {"name": "kept", "status": "Running", "type": "virtual-machine"}}
    calls = []
    fail_import = False
    fail_alias_update = False

    def fake_incus(*arguments, input=None):
        calls.append((arguments, input))
        if arguments[:2] == ("storage", "list"):
            return json.dumps([{"name": "consumer-pool"}])
        if arguments[0] == "list":
            return json.dumps(list(instances.values()))
        if arguments[:3] == ("image", "alias", "list"):
            return json.dumps(list(aliases.values()))
        if arguments[:2] == ("image", "list"):
            return json.dumps(list(images.values()))
        if arguments[:2] == ("image", "import"):
            if fail_import:
                raise RuntimeError("fake import failure")
            assert arguments[2:4] == (str(metadata), str(disk)) or arguments[3].endswith("new-disk.qcow2")
            name = arguments[-1]
            target = hashlib.sha256(Path(arguments[2]).read_bytes() + Path(arguments[3]).read_bytes()).hexdigest()
            if target in images:
                raise RuntimeError("Image with same fingerprint already exists")
            images[target] = {"fingerprint": target, "type": "virtual-machine"}
            aliases[name] = {"name": name, "target": target, "type": "virtual-machine"}
        elif arguments[:3] == ("image", "alias", "create"):
            name, target = arguments[3:5]
            assert target in images
            aliases[name] = {"name": name, "target": target, "type": images[target]["type"]}
        elif arguments[:3] == ("image", "alias", "rename"):
            entry = aliases.pop(arguments[3])
            entry["name"] = arguments[4]
            aliases[arguments[4]] = entry
        elif arguments[:3] == ("image", "alias", "delete"):
            aliases.pop(arguments[3])
        elif arguments[0] == "query":
            if fail_alias_update:
                raise RuntimeError("fake alias update failure")
            assert arguments[1].endswith("?project=default")
            name = unquote(arguments[1].rsplit("/", 1)[1].split("?", 1)[0])
            aliases[name].update(json.loads(arguments[-1]))
            aliases[name]["type"] = images[aliases[name]["target"]]["type"]
        elif arguments[0] == "launch":
            assert "--vm" in arguments
            instances[arguments[2]] = {"name": arguments[2], "status": "Running", "type": "virtual-machine"}
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
        assert module.condition("consumer-pool") == 1
        try:
            module.condition("missing")
        except RuntimeError as error:
            assert "explicit storage migration" in str(error)
        else:
            raise AssertionError("Foreign pool allowed preseed")
        with patch.object(module, "incus", return_value="[]"):
            assert module.condition("missing") == 0
        stamps = root / "stamps"
        fail_alias_update = True
        try:
            module.provision(manifest, str(stamps))
        except RuntimeError as error:
            assert "alias update failure" in str(error)
        else:
            raise AssertionError("Alias failure was ignored")
        assert fingerprint in images and aliases["consumer-image"]["target"] == "old-image"
        assert not (stamps / "image-consumer-image.source").exists()
        calls.clear()
        fail_alias_update = False
        module.provision(manifest, str(stamps))
        assert not any(args[:2] == ("image", "import") for args, _ in calls)
        assert aliases["consumer-image"]["target"] == fingerprint and aliases["consumer-image"]["description"] == "keep"
        assert [args[2] for args, _ in calls if args[0] == "launch"] == ["new"]
        assert not any(args[0] in ("delete", "stop") for args, _ in calls)
        calls.clear()
        instances["kept"]["status"] = "Stopped"
        module.provision(manifest, str(stamps))
        assert ("start", "kept") in [args for args, _ in calls]
        assert not any(args[0] == "launch" or args[:2] == ("image", "import") for args, _ in calls)
        # Removed declarations are not guest deletion requests.
        calls.clear()
        module.provision({"virtualMachines": {}}, str(stamps))
        assert set(instances) == {"kept", "new"}
        # All existing targets are type-checked before any import, launch or device mutation.
        instances["kept"]["type"] = "container"
        calls.clear()
        try:
            module.provision(manifest, str(root / "must-not-exist"))
        except RuntimeError as error:
            assert "kept" in str(error) and "expected virtual-machine" in str(error)
        else:
            raise AssertionError("Container was silently accepted or replaced")
        assert [args[0] for args, _ in calls] == ["list"]
        assert not (root / "must-not-exist").exists()
        assert instances["kept"]["type"] == "container"
        instances["kept"]["type"] = "virtual-machine"
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
        newer = root / "new-disk.qcow2"
        newer.write_bytes(b"new source")
        fail_import = True
        changed = {"virtualMachines": {"kept": {**definition, "disk": str(newer)}}}
        try:
            module.provision(changed, str(stamps))
        except RuntimeError:
            pass
        else:
            raise AssertionError("Import failure was ignored")
        assert stamp.read_bytes() == old_stamp and aliases["consumer-image"]["target"] == fingerprint
        # Content matches are reusable only when the stored image is actually a VM.
        images[fingerprint]["type"] = "container"
        calls.clear()
        try:
            module.ensure_image("wrong-type", (str(metadata), str(disk)), stamps)
        except ValueError as error:
            assert "virtual-machine" in str(error)
        else:
            raise AssertionError("Wrong image type accepted")
        assert not any(args[:2] == ("image", "import") or args[:3] == ("image", "alias", "create") for args, _ in calls)

    # Standard metadata/qcow2 output directory discovery; container rootfs is rejected.
    output = root / "image-output"
    (output / "tarball").mkdir(parents=True)
    (output / "tarball" / "metadata.tar.xz").write_bytes(b"metadata")
    (output / "nixos.qcow2").write_bytes(b"disk")
    assert module.image_file(str(output), metadata=True) == output / "tarball" / "metadata.tar.xz"
    assert module.image_file(str(output)) == output / "nixos.qcow2"
    (output / "second.qcow2").write_bytes(b"disk")
    rootfs = root / "rootfs.squashfs"
    rootfs.write_bytes(b"container")
    for invalid in (str(rootfs), str(output)):
        try:
            module.image_file(invalid)
        except ValueError:
            pass
        else:
            raise AssertionError("Invalid or ambiguous disk image accepted")
    try:
        module.validate({"virtualMachines": {"bad": {**definition, "launchConfig": {"type": "container"}}}})
    except ValueError:
        pass
    else:
        raise AssertionError("Container launch config accepted")
    # Verify the actual ExecCondition CLI error status, not a skip/success code.
    executable = root / "incus"
    executable.write_text("#!/bin/sh\nprintf 'not-json\\n'\n")
    executable.chmod(0o755)
    result = subprocess.run([sys.executable, str(script), "condition", "consumer-pool"], env={**os.environ, "PATH": str(root) + os.pathsep + os.environ["PATH"]}, capture_output=True)
    assert result.returncode == 255
print("incus provisioning: OK")
