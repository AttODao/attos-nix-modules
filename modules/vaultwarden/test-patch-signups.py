#!/usr/bin/env python3
"""Isolated signup patch checks; fixtures are synthetic, never real secrets."""
import importlib.util
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
from unittest.mock import patch as mock_patch

script = Path(__file__).with_name("patch-signups.py")
spec = importlib.util.spec_from_file_location("signup_patch", script)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

with tempfile.TemporaryDirectory() as directory:
    path = Path(directory) / "config.json"
    module.patch(path, False)
    assert json.loads(path.read_text()) == {"signups_allowed": False, "signups_domains_whitelist": ""}
    assert stat.S_IMODE(path.stat().st_mode) == 0o600
    original = {
        "signups_allowed": True,
        "signups_verify": False,
        "signups_domains_whitelist": "example.test",
        "sso_signups_allowed": True,
        "invitations_allowed": True,
        "admin_token": "$argon2id$synthetic-fixture",
        "smtp_password": "synthetic-secret",
        "other": {"unicode": "日本語", "array": [1, None, True]},
    }
    path.write_text(json.dumps(original))
    path.chmod(0o640)
    before = path.stat()
    module.patch(path, False)
    disabled = original | {"signups_allowed": False, "signups_domains_whitelist": ""}
    assert json.loads(path.read_text()) == disabled
    after = path.stat()
    assert (after.st_uid, after.st_gid, stat.S_IMODE(after.st_mode)) == (
        before.st_uid, before.st_gid, 0o640
    )
    assert after.st_ino != before.st_ino  # replacement, not in-place truncation
    module.patch(path, False)
    assert path.stat().st_ino == after.st_ino  # idempotent
    module.patch(path, True)
    assert json.loads(path.read_text()) == disabled | {"signups_allowed": True}
    # True preserves a pre-existing whitelist, even when flipping the boolean.
    path.write_text(json.dumps(original | {"signups_allowed": False}))
    module.patch(path, True)
    assert json.loads(path.read_text()) == original
    unchanged = path.stat().st_ino
    module.patch(path, True)
    assert path.stat().st_ino == unchanged
    # False already set must still clear the whitelist (the old early return bug).
    path.write_text(json.dumps(original | {"signups_allowed": False}))
    module.patch(path, False)
    assert json.loads(path.read_text()) == disabled
    # Persisted empty whitelist overrides a nonempty runtime environment whitelist.
    env = {"signups_allowed": True, "signups_domains_whitelist": "environment.test"}
    effective = env | json.loads(path.read_text())
    assert not effective["signups_allowed"] and effective["signups_domains_whitelist"] == ""
    for invalid in (
        '{"admin_token":"synthetic-secret",', '[]', 'null',
        '{"admin_token":"first", "admin_token":"synthetic-secret"}',
        '{"other": NaN}',
    ):
        path.write_text(invalid)
        result = subprocess.run([sys.executable, script, path, "false"], capture_output=True)
        assert result.returncode != 0 and not result.stdout
        assert b"synthetic-secret" not in result.stderr
        assert path.read_text() == invalid
    path.write_text(json.dumps(original))
    original_bytes = path.read_bytes()
    with mock_patch.object(module.os, "replace", side_effect=OSError("synthetic failure")):
        try:
            module.patch(path, False)
        except OSError:
            pass
        else:
            raise AssertionError("failed replacement must fail closed")
    assert path.read_bytes() == original_bytes
    assert not list(Path(directory).glob(".config-signups-*"))
    real_mkstemp = module.tempfile.mkstemp
    def concurrent_write(*args, **kwargs):
        path.write_text('{"other": "concurrent update"}')
        return real_mkstemp(*args, **kwargs)
    for existed in (True, False):
        if not existed:
            path.unlink()
        with mock_patch.object(module.tempfile, "mkstemp", side_effect=concurrent_write):
            try:
                module.patch(path, False)
            except ValueError:
                pass
            else:
                raise AssertionError("concurrent update must not be overwritten")
        assert json.loads(path.read_text()) == {"other": "concurrent update"}
        assert not list(Path(directory).glob(".config-signups-*"))
    # Preserve symlink targets and reject symlinks (including dangling ones).
    path.unlink()
    target = Path(directory) / "target.json"
    target.write_bytes(original_bytes)
    path.symlink_to(target)
    result = subprocess.run([sys.executable, script, path, "false"], capture_output=True)
    assert result.returncode != 0 and target.read_bytes() == original_bytes
    target.unlink()
    result = subprocess.run([sys.executable, script, path, "false"], capture_output=True)
    assert result.returncode != 0 and path.is_symlink()
    path.unlink()
    path.mkdir()
    result = subprocess.run([sys.executable, script, path, "false"], capture_output=True)
    assert result.returncode != 0 and path.is_dir()
print("Vaultwarden signup patch tests passed")
