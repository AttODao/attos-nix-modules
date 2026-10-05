#!/usr/bin/env python3
"""Atomically derive Radicale authentication from runtime mail hash files."""

import grp
import os
from pathlib import Path
import re
import sys
import tempfile

BCRYPT = re.compile(rb"\$2[aby]\$(?:0[4-9]|[12][0-9]|3[01])\$[./A-Za-z0-9]{53}")


def generate(target, accounts, gid):
    target = Path(target)
    # Validate every input before replacing the existing authentication file.
    lines = []
    for name, source in accounts:
        if not name or any(c in name for c in ":\r\n\x00"):
            raise ValueError("Invalid Radicale account name")
        with open(source, "rb") as stream:
            password_hash = stream.read(62).removesuffix(b"\n")
        if not BCRYPT.fullmatch(password_hash):
            raise ValueError(f"Radicale requires a bcrypt hash for {name} in {source}")
        lines.append(name.encode("utf-8") + b":" + password_hash + b"\n")

    fd, temporary = tempfile.mkstemp(prefix="users.", dir=target.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            os.fchmod(stream.fileno(), 0o640)
            os.fchown(stream.fileno(), os.geteuid(), gid)
            stream.writelines(lines)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, target)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


if __name__ == "__main__":
    if len(sys.argv) < 3 or (len(sys.argv) - 3) % 2:
        sys.exit("usage: radicale-users.py TARGET GROUP [ACCOUNT HASH_FILE ...]")
    try:
        generate(sys.argv[1], zip(sys.argv[3::2], sys.argv[4::2]), grp.getgrnam(sys.argv[2]).gr_gid)
    except (OSError, ValueError, KeyError) as error:
        sys.exit(str(error))
