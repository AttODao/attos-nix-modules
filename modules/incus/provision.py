#!/usr/bin/env python3
"""Create-only Incus KVM VM provisioning; never convert or delete instances."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from urllib.parse import quote
import uuid


def incus(*arguments, input=None):
    result = subprocess.run(["incus", "--force-local", "--project", "default", *arguments], input=input, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode:
        raise RuntimeError("Incus operation failed: " + " ".join(arguments[:2]))
    return result.stdout


def condition(pool):
    pools = json.loads(incus("storage", "list", "--format=json"))
    if not isinstance(pools, list) or not all(isinstance(item, dict) and isinstance(item.get("name"), str) for item in pools):
        raise ValueError("Unexpected Incus storage list")
    # ExecCondition 1 skips initialization; errors must use 255, not a skip code.
    if any(item["name"] == pool for item in pools):
        return 1
    if pools:
        raise RuntimeError("Target pool is absent while other pools exist; explicit storage migration is required before preseed.")
    return 0


def image_file(value, metadata=False):
    path = Path(value)
    if not path.is_absolute():
        raise ValueError("Incus image paths must be absolute")
    if path.is_file():
        if not metadata and path.suffix != ".qcow2":
            raise ValueError("Incus VM disk must be a qcow2 image")
        return path
    matches = sorted(path.rglob("tarball/*.tar.xz") if metadata else path.glob("*.qcow2"))
    if len(matches) != 1:
        raise ValueError("Expected exactly one Incus image archive under " + str(path))
    return matches[0]


def validate(manifest):
    virtual_machines = manifest.get("virtualMachines")
    if not isinstance(virtual_machines, dict):
        raise ValueError("Expected an Incus virtualMachines map")
    aliases = {}
    for name, definition in virtual_machines.items():
        if not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9-]{0,62}", name):
            raise ValueError("Invalid Incus instance name")
        alias = definition["alias"]
        if not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9._-]*", alias):
            raise ValueError("Invalid local Incus image alias")
        launch = definition["launchConfig"]
        managed = definition["managedDeviceNames"]
        if not isinstance(launch, dict) or not isinstance(managed, list) or len(set(managed)) != len(managed):
            raise ValueError("Invalid Incus launch configuration or managed device list")
        if launch.get("type", "virtual-machine") != "virtual-machine":
            raise ValueError("Incus launchConfig type must be virtual-machine")
        devices = launch.get("devices", {})
        if not isinstance(devices, dict):
            raise ValueError("Expected native Incus devices")
        for device in managed:
            if not isinstance(device, str) or not re.fullmatch(r"[a-zA-Z0-9_.-]+", device):
                raise ValueError("Invalid Incus managed device name")
            if device not in devices or not isinstance(devices[device], dict) or not devices[device].get("type"):
                raise ValueError("Managed devices must have a native type in launchConfig.devices")
        source = (str(image_file(definition["metadata"], metadata=True)), str(image_file(definition["disk"])))
        if alias in aliases and aliases[alias] != source:
            raise ValueError("One Incus image alias cannot refer to different image sources")
        aliases[alias] = source
    return virtual_machines, aliases


def atomic_stamp(path, value):
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as handle:
            temporary = Path(handle.name)
            handle.write(value + "\n")
        os.replace(temporary, path)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def alias_list():
    values = json.loads(incus("image", "alias", "list", "--format=json"))
    if not isinstance(values, list) or not all(isinstance(item.get("name"), str) and isinstance(item.get("target"), str) for item in values):
        raise ValueError("Unexpected Incus alias list")
    return {item["name"]: item for item in values}


def ensure_image(alias, source, state_dir):
    stamp = state_dir / ("image-" + alias + ".source")
    source_key = "|".join(source)
    aliases = alias_list()
    if alias in aliases and stamp.is_file() and stamp.read_text().strip() == source_key:
        return
    temporary = alias + "-attos-" + uuid.uuid4().hex[:12]
    # Import first, then change the alias atomically. A failed import keeps the old image usable.
    incus("image", "import", *source, "--alias", temporary)
    imported = alias_list().get(temporary)
    if imported is None:
        raise RuntimeError("Imported Incus image alias is missing")
    if alias in aliases:
        incus("query", "/1.0/images/aliases/" + quote(alias, safe="") + "?project=default", "-X", "PUT", "-d", json.dumps({
            "target": imported["target"], "description": aliases[alias].get("description", ""),
        }))
        incus("image", "alias", "delete", temporary)
    else:
        incus("image", "alias", "rename", temporary, alias)
    # ponytail: retain superseded images; add explicit GC only with a consumer-owned retention policy.
    atomic_stamp(stamp, source_key)


def provision(manifest, directory):
    virtual_machines, sources = validate(manifest)
    current = json.loads(incus("list", "--format=json"))
    if not isinstance(current, list) or not all(isinstance(item.get("name"), str) for item in current):
        raise ValueError("Unexpected Incus instance list")
    instances = {item["name"]: item for item in current}
    for name in virtual_machines.keys() & instances.keys():
        if instances[name].get("type") != "virtual-machine":
            raise RuntimeError("Incus instance " + name + " has type " + str(instances[name].get("type")) + "; expected virtual-machine. Existing instances are never converted or deleted.")
        if instances[name].get("status") not in ("Running", "Stopped"):
            raise RuntimeError("Refusing to change an Incus instance in state " + str(instances[name].get("status")))
    state_dir = Path(directory)
    if not state_dir.is_absolute():
        raise ValueError("Incus stamp directory must be absolute")
    state_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    for alias, source in sources.items():
        ensure_image(alias, source, state_dir)
    for name, definition in virtual_machines.items():
        if name not in instances:
            incus("launch", definition["alias"], name, "--vm", "--quiet", input=json.dumps(definition["launchConfig"]))
        managed = definition["managedDeviceNames"]
        if managed:
            existing = incus("config", "device", "list", name).splitlines()
            for device in managed:
                fields = definition["launchConfig"]["devices"][device]
                values = [key + "=" + (value if isinstance(value, str) else json.dumps(value)) for key, value in fields.items() if key != "type"]
                if device in existing:
                    if values:
                        incus("config", "device", "set", name, device, *values)
                else:
                    incus("config", "device", "add", name, device, fields["type"], *values)
        if name in instances and instances[name]["status"] == "Stopped":
            incus("start", name)


def main():
    operation, *arguments = sys.argv[1:]
    if operation == "condition" and len(arguments) == 1:
        return condition(arguments[0])
    if operation == "provision" and len(arguments) == 2:
        with open(arguments[0], encoding="utf-8") as handle:
            provision(json.load(handle), arguments[1])
        return 0
    raise ValueError("Usage: attos-incus condition <pool> | provision <manifest> <state-directory>")


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        print("Incus provisioning failed: " + str(error), file=sys.stderr)
        # An ExecCondition daemon/parser failure must fail the unit instead of permitting initialization.
        sys.exit(255)
