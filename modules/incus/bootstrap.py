#!/usr/bin/env python3
"""Explicit initial login/credential setup; never replace existing authentication."""
import argparse
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import subprocess
import sys

from rebuild import guest, require_running, run


INSTALL = r'''
set -eu
umask 077
home=$1
destination=$2
case "$(realpath -m -- "$destination")" in "$home"/*) ;; *) exit 1 ;; esac
if [ -e "$destination" ] || [ -L "$destination" ]; then exit 3; fi
parent=$(dirname -- "$destination")
mkdir -p -m 0700 -- "$parent"
temporary=$(mktemp "$parent/.vm-bootstrap.XXXXXXXX")
trap 'rm -f -- "$temporary"' EXIT HUP INT TERM
cat > "$temporary"
# A hard link publishes atomically without replacing an existing file, even on a race.
ln -- "$temporary" "$destination"
'''


def main():
    preliminary = argparse.ArgumentParser(add_help=False)
    preliminary.add_argument("--config", required=True)
    known, arguments = preliminary.parse_known_args()
    config = json.loads(Path(known.config).read_text())
    parser = argparse.ArgumentParser(prog="vm-bootstrap")
    parser.add_argument("virtual_machine", choices=config["virtualMachines"])
    actions = parser.add_subparsers(dest="action", required=True)
    password = actions.add_parser("passwd", help="set an unset/locked login password interactively")
    password.add_argument("user")
    credential = actions.add_parser("file", help="install a private runtime file under the user's home, without overwriting")
    credential.add_argument("user")
    credential.add_argument("source")
    credential.add_argument("destination", help="relative path under the guest user's home")
    units = credential.add_mutually_exclusive_group()
    units.add_argument("--system-unit", help="system service to start after installing the file")
    units.add_argument("--user-unit", help="user service to start after installing the file")
    args = parser.parse_args(arguments)
    try:
        if not re.fullmatch(r"[a-z_][a-z0-9_-]*\$?", args.user):
            raise ValueError("Invalid guest username")
        require_running(args.virtual_machine)
        account = run(guest(args.virtual_machine, ["getent", "passwd", args.user]), capture=True).strip().split(":")
        if len(account) != 7 or account[0] != args.user:
            raise ValueError("Unexpected guest account")
        uid, gid, home, shell = int(account[2]), int(account[3]), account[5], account[6]
        # ponytail: standard login UID range; use declared account metadata if low-UID logins are needed.
        if uid < 1000 or PurePosixPath(shell).name in ("nologin", "false") or not home.startswith("/") or home == "/":
            raise ValueError("Only ordinary guest login accounts may be bootstrapped")
        if args.action == "passwd":
            status = run(guest(args.virtual_machine, ["passwd", "--status", "--", args.user]), capture=True).split()
            if len(status) < 2 or status[0] != args.user or status[1] not in ("P", "L", "NP"):
                raise ValueError("Unexpected guest password status")
            if status[1] == "P":
                print("Existing password preserved")
                return 0
            # L can also mean a locked *existing* hash; never replace that authentication.
            run(guest(args.virtual_machine, ["awk", "-F:", "-v", "login=" + args.user,
                '$1 == login && ($2 == "" || $2 == "!" || $2 == "!!" || $2 == "*") { unset = 1 } END { exit !unset }',
                "/etc/shadow"]))
            if not sys.stdin.isatty():
                raise ValueError("Password setup requires a terminal; do not pipe passwords")
            run(guest(args.virtual_machine, ["passwd", "--", args.user], interactive=True))
            return 0
        destination = PurePosixPath(args.destination)
        if destination.is_absolute() or any(part in ("", ".", "..") for part in args.destination.split("/")):
            raise ValueError("Destination must be a relative home path without dot segments")
        unit = args.system_unit or args.user_unit
        if unit and not re.fullmatch(r"[A-Za-z0-9_.@:-]+\.service", unit):
            raise ValueError("Expected a service unit name")
        with os.fdopen(os.open(args.source, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK), "rb") as source:
            info = os.fstat(source.fileno())
            if not stat.S_ISREG(info.st_mode) or stat.S_IMODE(info.st_mode) & 0o077:
                raise ValueError("Source must be a private regular file (0600 or stricter)")
            result = subprocess.run(guest(args.virtual_machine, [
                "/bin/sh", "-c", INSTALL, "vm-bootstrap", home, str(PurePosixPath(home) / destination)
            ], user=uid, group=gid), stdin=source)
        if result.returncode == 3:
            print("Existing credential file preserved; service not changed")
            return 0
        if result.returncode:
            raise RuntimeError("Guest credential installation failed")
        if args.system_unit:
            run(guest(args.virtual_machine, ["systemctl", "start", "--", unit]))
        elif args.user_unit:
            run(guest(args.virtual_machine, ["env", "XDG_RUNTIME_DIR=/run/user/" + str(uid),
                                           "systemctl", "--user", "start", "--", unit], user=uid, group=gid))
        print("Credential installed; no existing authentication was replaced")
        return 0
    except (OSError, ValueError, RuntimeError, KeyError, subprocess.CalledProcessError) as error:
        message = "Guest operation failed; existing authentication was not replaced" if isinstance(error, subprocess.CalledProcessError) else str(error)
        print("vm-bootstrap: " + message, file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
