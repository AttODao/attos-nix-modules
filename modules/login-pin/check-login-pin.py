#!@PYTHON@

import base64
import hashlib
import hmac
import os
import re
import sys
from pathlib import Path

ALLOWED_USERS = ["@ALLOWED_USERS@"]

user = os.environ.get("PAM_USER", "")

if user not in ALLOWED_USERS:
    sys.exit(1)

raw = sys.stdin.buffer.read(512)
pin = raw.split(b"\0", 1)[0].decode("utf-8", "ignore").strip()

if not re.fullmatch(r"\d{6}", pin):
    sys.exit(1)

path = Path("@PIN_HASH_DIRECTORY@") / f"{user}.pbkdf2"

try:
    stored = path.read_text().strip()
    algo, iterations_s, salt_b64, hash_b64 = stored.split("$", 3)
except (OSError, ValueError):
    sys.exit(1)

if algo != "pbkdf2_sha256":
    sys.exit(1)

try:
    iterations = int(iterations_s)
    salt = base64.b64decode(salt_b64, validate=True)
    expected = base64.b64decode(hash_b64, validate=True)
except (ValueError, TypeError):
    sys.exit(1)

if iterations < 100_000 or not salt or not expected:
    sys.exit(1)

actual = hashlib.pbkdf2_hmac(
    "sha256",
    pin.encode("utf-8"),
    salt,
    iterations,
)

if hmac.compare_digest(actual, expected):
    sys.exit(0)

sys.exit(1)
