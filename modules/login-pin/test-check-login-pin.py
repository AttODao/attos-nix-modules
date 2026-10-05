# Run with: python3 nixos/login-pin/test-check-login-pin.py
import base64
import hashlib
import os
from pathlib import Path
import subprocess
import sys
import tempfile

source = Path(__file__).with_name("check-login-pin.py").read_text()
with tempfile.TemporaryDirectory() as directory:
    checker = Path(directory) / "check.py"
    checker.write_text(source.replace('["@ALLOWED_USERS@"]', '["attodao"]')
                      .replace("@PIN_HASH_DIRECTORY@", directory))
    salt = b"test-salt"
    digest = hashlib.pbkdf2_hmac("sha256", b"123456", salt, 200000)
    encoded = lambda value: base64.b64encode(value).decode("ascii")
    stored = f"pbkdf2_sha256$200000${encoded(salt)}${encoded(digest)}"
    hash_file = Path(directory) / "attodao.pbkdf2"

    def check(pin, user="attodao"):
        return subprocess.run([sys.executable, str(checker)], input=pin,
                              env={**os.environ, "PAM_USER": user}).returncode

    assert check(b"123456") == 1  # Missing hash must fail closed.
    hash_file.write_text(stored)
    assert check(b"123456\0") == 0
    assert check(b"654321") == 1
    assert check(b"12345") == 1
    assert check(b"password") == 1
    assert check(b"123456", "root") == 1
    for invalid in ["invalid", stored.replace("200000", "1"),
                    stored.replace("pbkdf2_sha256", "sha256"),
                    "pbkdf2_sha256$200000$!$!"]:
        hash_file.write_text(invalid)
        assert check(b"123456") == 1
print("login-pin checker: OK")
