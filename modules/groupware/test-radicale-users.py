#!/usr/bin/env python3
import importlib.util
import os
from pathlib import Path
import stat
import tempfile

spec = importlib.util.spec_from_file_location("radicale_users", Path(__file__).with_name("radicale-users.py"))
users = importlib.util.module_from_spec(spec)
spec.loader.exec_module(users)

with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    source = root / "password"
    source.write_text("$2b$12$" + "A" * 53 + "\n")
    target = root / "users"
    users.generate(target, [("alice@example.test", source)], os.getgid())
    old = target.read_bytes()
    assert old == b"alice@example.test:" + source.read_bytes()
    assert stat.S_IMODE(target.stat().st_mode) == 0o640 and target.stat().st_gid == os.getgid()
    for name, value in (("alice@example.test", "not-bcrypt"), ("bad:name", "$2b$12$" + "A" * 53)):
        source.write_text(value)
        try:
            users.generate(target, [(name, source)], os.getgid())
        except ValueError:
            pass
        else:
            raise AssertionError("Invalid authentication input was accepted")
        assert target.read_bytes() == old
        assert list(root.glob("users.*")) == []
print("radicale authentication: OK")
