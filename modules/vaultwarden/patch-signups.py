#!/usr/bin/env python3
"""Patch only the signup policy before Vaultwarden starts; never log config data."""
import json
import os
from pathlib import Path
import stat
import sys
import tempfile


def object_from_pairs(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate configuration key")
        result[key] = value
    return result


def patch(path, allowed):
    path = Path(path)
    previous = None
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    except FileNotFoundError:
        config = {}
    else:
        with os.fdopen(fd) as source:
            previous = os.fstat(source.fileno())
            if not stat.S_ISREG(previous.st_mode):
                raise ValueError("not a regular configuration file")
            config = json.load(source, object_pairs_hook=object_from_pairs)
        if not isinstance(config, dict):
            raise ValueError("configuration must be an object")
        if config.get("signups_allowed") is allowed and (
            allowed or config.get("signups_domains_whitelist") == ""
        ):
            return
    config["signups_allowed"] = allowed
    # Upstream gives this whitelist precedence over signups_allowed, including ENV.
    if not allowed:
        config["signups_domains_whitelist"] = ""
    fd, temporary = tempfile.mkstemp(prefix=".config-signups-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as target:
            json.dump(config, target, ensure_ascii=False, indent=2, allow_nan=False)
            target.write("\n")
            target.flush()
            if previous is not None:
                os.fchown(target.fileno(), previous.st_uid, previous.st_gid)
            os.fchmod(target.fileno(), stat.S_IMODE(previous.st_mode) if previous else 0o600)
            os.fsync(target.fileno())
        # Fail closed rather than overwrite a file changed during preparation.
        current = path.lstat() if path.exists() or path.is_symlink() else None
        if previous is None:
            if current is not None:
                raise ValueError("configuration appeared during preparation")
        elif current is None or (current.st_dev, current.st_ino, current.st_mtime_ns, current.st_size) != (
            previous.st_dev, previous.st_ino, previous.st_mtime_ns, previous.st_size
        ):
            raise ValueError("configuration changed during preparation")
        os.replace(temporary, path)
        directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


if __name__ == "__main__":
    try:
        if len(sys.argv) != 3 or sys.argv[2] not in ("true", "false"):
            raise ValueError("invalid arguments")
        patch(sys.argv[1], sys.argv[2] == "true")
    except (OSError, ValueError, TypeError):
        # JSON and credentials must never reach the journal, even on failure.
        sys.exit("Vaultwarden signup policy patch failed; check runtime configuration before retrying.")
