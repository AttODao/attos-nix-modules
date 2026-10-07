#!/usr/bin/env python3
"""Mock libnm creation and nmcli cleanup; no actual bus, network or keys are used."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

spec = importlib.util.spec_from_file_location(
    "import_tunnels", Path(__file__).with_name("import-tunnels.py")
)
import_tunnels = importlib.util.module_from_spec(spec)
spec.loader.exec_module(import_tunnels)


class NmcliMock:
    def __init__(self):
        self.profiles = {}
        self.calls = []
        self.import_fails = False
        self.malformed_uuid = False
        self.next_uuid = "11111111-2222-3333-4444-555555555555"

    def __call__(self, command, *, stdout, stderr, env, text):
        self.calls.append(command)
        self.last_stderr = stderr
        args = command[1:]
        if args[:2] == ["connection", "show"]:
            selector, value = args[2:]
            exists = value in (self.profiles if selector == "id" else self.profiles.values())
            return self.result(0 if exists else 10)
        if args[:2] == ["connection", "delete"]:
            selector, value = args[2], args[3]
            if selector == "id":
                existed = self.profiles.pop(value, None) is not None
            else:
                existed = any(uuid == value for uuid in self.profiles.values())
                self.profiles = {k: v for k, v in self.profiles.items() if v != value}
            return self.result(0 if existed else 10)
        raise AssertionError(f"unexpected nmcli call: {command!r}")

    @staticmethod
    def result(code, out=""):
        return subprocess.CompletedProcess(["nmcli"], code, out, "")


class ImportTunnelTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.runtime = self.root / "runtime"
        self.creds = self.root / "creds"
        self.runtime.mkdir(mode=0o700)
        self.creds.mkdir(mode=0o700)
        self.addCleanup(os.umask, os.umask(0o077))
        (self.creds / "tunnel-0").write_text("mock config, deliberately not a real key\n")
        self.tunnels = [{"name": "wg0", "credential": "tunnel-0"}]
        self.nm = NmcliMock()
        self.created = []
        self.activation_eligible = []
        self.add_fails = False
        self.client = Mock()
        self.client.add_connection2.side_effect = self.add_profile
        self.loop = SimpleNamespace(run=self.complete_add, quit=Mock())
        self.gi = Mock()
        self.native = SimpleNamespace(
            conn_wireguard_import=Mock(side_effect=self.native_import),
            Client=SimpleNamespace(new=Mock(return_value=self.client)),
            ConnectionSerializationFlags=SimpleNamespace(ALL=0),
            SettingsAddConnection2Flags=SimpleNamespace(IN_MEMORY=2, BLOCK_AUTOCONNECT=32),
        )
        repository = SimpleNamespace(NM=self.native, GLib=SimpleNamespace(MainLoop=lambda: self.loop))
        self.addCleanup(patch.stopall)
        patch.dict("sys.modules", {"gi": self.gi, "gi.repository": repository}).start()
        patch.object(import_tunnels.subprocess, "run", side_effect=self.nm).start()
        patch.object(import_tunnels.secrets, "token_hex", return_value="123456789abc").start()

    def native_import(self, filename):
        config = Path(filename)
        self.assertEqual(config.read_text(), (self.creds / "tunnel-0").read_text())
        self.assertEqual(config.stat().st_mode & 0o777, 0o600)
        if self.nm.import_fails:
            raise RuntimeError("private-key=mock-secret-input")
        # Match libnm's default: imports start out with autoconnect=true.
        properties = {"id": config.stem, "interface-name": config.stem, "autoconnect": True}
        connection = Mock()
        connection.get_setting_connection.return_value.set_property.side_effect = properties.__setitem__
        connection.get_uuid.return_value = "not-a-uuid" if self.nm.malformed_uuid else self.nm.next_uuid
        connection.to_dbus.side_effect = lambda flags: dict(properties, uuid=connection.get_uuid())
        return connection

    def add_profile(self, settings, flags, args, ignore_out_result, cancellable, callback, data):
        # Model immediate eligibility AT CREATION, not after a later modify.
        self.activation_eligible.append(settings["autoconnect"] and not flags & 32)
        record = self.runtime / "wg123456789abc.uuid"
        self.created.append((settings.copy(), flags, record.read_text()))
        self.nm.profiles[settings["id"]] = settings["uuid"]
        self.assertIsNone(args)
        self.assertFalse(ignore_out_result)  # Require AddConnection2, no legacy fallback.
        self.assertIsNone(cancellable)
        self.callback = lambda: callback(self.client, object(), data)
        self.client.add_connection2_finish.side_effect = (
            RuntimeError("private-key=mock-secret-input") if self.add_fails else None
        )

    def complete_add(self):
        self.callback()
        self.loop.quit.assert_called()

    def test_success_imports_temporary_profile_and_stop_deletes_owned_uuid(self):
        import_tunnels.start(self.runtime, self.tunnels, self.creds)
        self.assertEqual(self.nm.profiles, {"WireGuard: wg0": self.nm.next_uuid})
        self.assertEqual((self.runtime / "wg123456789abc.uuid").read_text(), self.nm.next_uuid + "\n")
        self.assertFalse(list(self.runtime.glob("*.conf")))
        self.gi.require_version.assert_called_once_with("NM", "1.0")
        self.assertTrue(import_tunnels.cleanup(self.runtime))
        self.assertEqual(self.nm.profiles, {})
        self.assertFalse(list(self.runtime.glob("*.uuid")))

    def test_creation_already_denies_immediate_autoconnect(self):
        import_tunnels.start(self.runtime, self.tunnels, self.creds)
        settings, flags, record = self.created[0]
        self.assertFalse(settings["autoconnect"])
        self.assertEqual(settings["id"], "WireGuard: wg0")
        self.assertEqual(settings["interface-name"], "wg0")
        self.assertEqual(flags, 2 | 32)  # IN_MEMORY | BLOCK_AUTOCONNECT, never TO_DISK.
        self.assertEqual(record, settings["uuid"] + "\n")  # Ownership precedes add.
        self.assertEqual(self.activation_eligible, [False])
        self.assertFalse(any("import" in call or "modify" in call for call in self.nm.calls))
        # A restart cleans the prior UUID before recreating; no duplicate profile.
        import_tunnels.start(self.runtime, self.tunnels, self.creds)
        self.assertEqual(self.nm.profiles, {"WireGuard: wg0": self.nm.next_uuid})
        self.assertEqual(self.activation_eligible, [False, False])

    def test_malformed_uuid_response_cleans_pending_import_by_temporary_id(self):
        # UUID now comes from the local native importer, before daemon creation.
        self.nm.malformed_uuid = True
        with self.assertRaises(RuntimeError):
            import_tunnels.start(self.runtime, self.tunnels, self.creds)
        self.assertEqual(self.created, [])
        self.assertEqual(self.nm.profiles, {})
        self.assertFalse(list(self.runtime.glob("*.uuid")))
        self.assertIn(["nmcli", "connection", "delete", "id", "wg123456789abc"], self.nm.calls)

    def test_import_failure_removes_pending_record_and_runtime_copy(self):
        for failure in ("parser", "add-reply"):
            with self.subTest(failure=failure):
                self.nm.import_fails = failure == "parser"
                self.add_fails = failure == "add-reply"
                with self.assertRaisesRegex(RuntimeError, "^NetworkManager import failed$"):
                    import_tunnels.start(self.runtime, self.tunnels, self.creds)
                self.assertEqual(self.nm.profiles, {})
                self.assertFalse(list(self.runtime.iterdir()))

    def test_cleanup_does_not_delete_unrelated_profiles(self):
        unrelated = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        self.nm.profiles["WireGuard: wg0"] = unrelated
        (self.runtime / "wg123456789abc.uuid").write_text("")
        self.assertTrue(import_tunnels.cleanup(self.runtime))
        self.assertEqual(self.nm.profiles, {"WireGuard: wg0": unrelated})
        # Even a native UUID collision must not claim/delete an existing profile.
        self.nm.next_uuid = unrelated
        with self.assertRaises(RuntimeError):
            import_tunnels.start(self.runtime, self.tunnels, self.creds)
        self.assertEqual(self.nm.profiles, {"WireGuard: wg0": unrelated})

    def test_main_suppresses_secret_tool_output(self):
        metadata = self.root / "tunnels.json"
        metadata.write_text(json.dumps(self.tunnels))
        for failure in ("parser", "add-reply"):
            with self.subTest(failure=failure):
                self.nm.import_fails = failure == "parser"
                self.add_fails = failure == "add-reply"
                with patch.dict(os.environ, {"CREDENTIALS_DIRECTORY": str(self.creds)}), \
                     patch("sys.argv", ["import-tunnels", "start", str(self.runtime), str(metadata)]), \
                     patch("sys.stderr") as stderr:
                    self.assertEqual(import_tunnels.main(), 1)
                output = "".join(str(call.args[0]) for call in stderr.write.call_args_list if call.args)
                self.assertIn("tool output suppressed", output)
                self.assertNotIn("mock-secret-input", output)
                self.assertNotIn("private-key", output.lower())
                self.assertIs(self.nm.last_stderr, subprocess.DEVNULL)


if __name__ == "__main__":
    unittest.main()
