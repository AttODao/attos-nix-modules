"""Root-only service preparation; never print the key."""
import os
import stat
import sys


def main():
    source, runtime, group = sys.argv[1:]
    fd = os.open(source, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd, "rb") as stream:
        info = os.fstat(stream.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_uid != 0 or info.st_gid != 0 or stat.S_IMODE(info.st_mode) != 0o400:
            raise SystemExit("apiKeyFile must be a regular root:root 0400 file")
        key = stream.read(8193)
    key = key.removesuffix(b"\n")
    if not key or len(key) > 8192 or any(c < 33 or c > 126 for c in key):
        raise SystemExit("apiKeyFile must contain one nonempty printable ASCII key (no whitespace)")
    secret = runtime + "/secret"
    os.makedirs(secret, mode=0o700, exist_ok=True)
    os.chmod(secret, 0o700)
    path = secret + "/environment"
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "wb") as stream:
        stream.write(b"API_KEY=" + key + b"\n")
    # A separate file is readable to the primary group, not the environment.
    log = runtime + "/console.log"
    fd = os.open(log, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o640)
    os.fchown(fd, 0, int(group))
    os.fchmod(fd, 0o640)
    os.close(fd)


if __name__ == "__main__":
    main()
