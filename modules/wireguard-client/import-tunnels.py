#!/usr/bin/env python3
"""Temporary NM profiles; only ownership records and runtime copies are written."""
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import subprocess
import sys

UUID = re.compile(r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}")
TEMP_NAME = re.compile(r"wg[0-9a-f]{12}")


def nmcli(*args, check=True):
    result = subprocess.run(
        ["nmcli", *args], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        env={**os.environ, "LC_ALL": "C"}, text=True,
    )
    if check and result.returncode:
        # Do not print tool output: an invalid config can put secret data in errors.
        raise RuntimeError("NetworkManager operation failed")
    return result


def parse_uuid(output):
    value = output.strip()
    if not UUID.fullmatch(value):
        raise RuntimeError("NetworkManager did not return a single UUID")
    return value


def cleanup(runtime):
    success = True
    for record in sorted(runtime.glob("*.uuid")):
        if not TEMP_NAME.fullmatch(record.stem):
            raise RuntimeError("Invalid profile ownership record")
        uuid = record.read_text().strip()
        if uuid:
            selector = ("uuid", parse_uuid(uuid))
        else:
            # Retain compatibility with pending records from the CLI importer.
            # Native imports record a UUID before adding any profile.
            selector = ("id", record.stem)
        result = nmcli("connection", "delete", *selector, check=False)
        if result.returncode in (0, 10):  # 10: already absent (e.g. NM restarted).
            record.unlink()
        else:
            success = False
    for config in runtime.glob("wg*.conf"):
        config.unlink()
    return success


def import_profile(config, name, record):
    # Lazy GI import: cleanup must still work if the native bindings fail to load.
    try:
        import gi
        gi.require_version("NM", "1.0")
        from gi.repository import GLib, NM

        connection = NM.conn_wireguard_import(str(config))
        setting = connection.get_setting_connection()
        setting.set_property("autoconnect", False)
        setting.set_property("id", "WireGuard: " + name)
        setting.set_property("interface-name", name)
        uuid = parse_uuid(connection.get_uuid())
        if nmcli("connection", "show", "uuid", uuid, check=False).returncode != 10:
            raise RuntimeError("Could not reserve profile UUID")
        # The native importer allocates the UUID locally. Record it atomically
        # BEFORE AddConnection2, including interruption/failed-reply cleanup.
        replacement = record.with_suffix(".new")
        replacement.write_text(uuid + "\n")
        replacement.replace(record)

        client = NM.Client.new(None)
        loop = GLib.MainLoop()
        failed = []

        def added(client, result, _data):
            try:
                client.add_connection2_finish(result)
            except Exception:
                failed.append(True)
            finally:
                loop.quit()

        client.add_connection2(
            connection.to_dbus(NM.ConnectionSerializationFlags.ALL),
            NM.SettingsAddConnection2Flags.IN_MEMORY | NM.SettingsAddConnection2Flags.BLOCK_AUTOCONNECT,
            None, False, None, added, None,
        )
        loop.run()
        if failed:
            raise RuntimeError("NetworkManager add failed")
    except Exception:
        # libnm parser/daemon errors may contain the input. Never propagate them.
        raise RuntimeError("NetworkManager import failed") from None


def start(runtime, tunnels, credentials):
    if not cleanup(runtime):
        raise RuntimeError("Could not clean up previous WireGuard profiles")
    try:
        for tunnel in tunnels:
            # A random basename satisfies the native importer and identifies
            # pending records; no profile is ever added under this temporary ID.
            temporary = "wg" + secrets.token_hex(6)
            existing = nmcli("connection", "show", "id", temporary, check=False)
            if existing.returncode != 10:
                raise RuntimeError("Could not reserve a temporary profile name")
            record = runtime / f"{temporary}.uuid"
            record.write_text("")
            config = runtime / f"{temporary}.conf"
            try:
                shutil.copyfile(credentials / tunnel["credential"], config)
                import_profile(config, tunnel["name"], record)
            finally:
                config.unlink(missing_ok=True)
    except Exception:
        cleanup(runtime)
        raise


def main():
    os.umask(0o077)
    runtime = Path(sys.argv[2])
    try:
        if sys.argv[1] == "start":
            start(runtime, json.loads(Path(sys.argv[3]).read_text()), Path(os.environ["CREDENTIALS_DIRECTORY"]))
        elif sys.argv[1] == "stop":
            if not cleanup(runtime):
                raise RuntimeError("WireGuard profile cleanup failed")
        else:
            raise RuntimeError("Unknown operation")
    except Exception:
        print("wireguard-client: operation failed (tool output suppressed)", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
