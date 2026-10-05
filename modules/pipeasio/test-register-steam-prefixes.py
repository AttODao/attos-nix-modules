#!/usr/bin/env python3
"""Run with python3; only temporary prefixes and mocked executables are used."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "register", Path(__file__).with_name("register-steam-prefixes.py")
)
register = importlib.util.module_from_spec(spec)
spec.loader.exec_module(register)


class RegistrationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.prefix = self.root / "steamapps/compatdata/123/pfx"
        self.dll = self.prefix / "drive_c/windows/system32/pipeasio64.dll"
        self.dll.parent.mkdir(parents=True)
        self.source = self.root / "pipeasio64.dll"
        self.source.write_bytes(b"new PE")
        self.dll.write_bytes(b"old PE")
        (self.prefix / "system.reg").write_text(
            '[Software\\\\ASIO\\\\PipeASIO] 123\n'
            f'"CLSID"="{register.PIPEASIO_REGISTRY_CLSID}"\n\n[Other]\n'
        )
        self.target = {
            "kind": "steam", "prefix": str(self.prefix), "runner": "/owning/proton",
            "error": "", "metadata": {"runtime_ready": True},
        }
        self.addCleanup(patch.stopall)
        patch.object(register, "DRIVER_DLL", self.source).start()

    def test_old_pe_is_not_skipped_and_registry_reads_never_start_wine(self):
        with patch.object(register.subprocess, "run") as run:
            self.assertFalse(register.prefix_is_current(self.prefix))
            self.dll.write_bytes(self.source.read_bytes())
            self.assertTrue(register.prefix_is_current(self.prefix))
            (self.prefix / "system.reg").write_text('[Other]\n"CLSID"="wrong"\n')
            self.assertFalse(register.prefix_is_current(self.prefix))
            run.assert_not_called()

    def test_registration_uses_owning_proton_and_restores_pe_on_failure(self):
        def fail(command, *, env, check):
            self.assertEqual(command, [str(register.PIPEASIO_REGISTER)])
            self.assertEqual(env["WINE"], str(register.PROTON_RUN))
            self.assertEqual(env["WINEPREFIX"], str(self.prefix))
            self.assertEqual(env["STEAM_COMPAT_DATA_PATH"], str(self.prefix.parent))
            self.assertEqual(env["PROTONPATH"], "/owning/proton")
            self.assertEqual(env["GAMEID"], "umu-0")
            self.assertNotIn("PIPEASIO_REGISTER_WITHOUT_LOADING", env)
            self.assertNotIn("STEAM_COMPAT_TOOL_PATHS", env)
            self.dll.write_bytes(b"partially installed PE")
            raise subprocess.CalledProcessError(1, command)

        with patch.dict(os.environ, {"PIPEASIO_REGISTER_WITHOUT_LOADING": "1", "STEAM_COMPAT_TOOL_PATHS": "wrong"}), patch.object(register.subprocess, "run", side_effect=fail):
            self.assertFalse(register.register_prefix(self.prefix, self.target))
        self.assertEqual(self.dll.read_bytes(), b"old PE")
        self.assertFalse(list(self.dll.parent.glob(".pipeasio-backup-*")))

    def test_success_refreshes_pe_and_symlinks_are_refused(self):
        with patch.object(register.subprocess, "run", side_effect=lambda *a, **k: self.dll.write_bytes(self.source.read_bytes())) as run:
            self.assertTrue(register.register_prefix(self.prefix, self.target))
            self.assertTrue(register.prefix_is_current(self.prefix))
            self.dll.unlink()
            self.dll.symlink_to(self.source)
            self.assertFalse(register.register_prefix(self.prefix, self.target))
            self.assertEqual(run.call_count, 1)

    def test_busy_prefix_is_detected_without_invoking_wine(self):
        proc = self.root / "proc"
        (proc / "123").mkdir(parents=True)
        (proc / "123/environ").write_bytes(f"WINEPREFIX={self.prefix}\0".encode())
        self.assertTrue(register.prefix_is_busy(self.prefix, proc))
        (proc / "123/environ").write_bytes(b"WINEPREFIX=/another/pfx\0")
        self.assertFalse(register.prefix_is_busy(self.prefix, proc))

    def test_unreadable_native_daemons_do_not_block_but_unknown_processes_do(self):
        proc = self.root / "proc"
        process = proc / "123"
        process.mkdir(parents=True)
        with patch.object(Path, "read_bytes", side_effect=PermissionError):
            for name in ["systemd", "(sd-pam)", "Hyprland", ".Hyprland-wrapp", "ssh-agent"]:
                (process / "comm").write_text(name)
                self.assertFalse(register.prefix_is_busy(self.prefix, proc))
            for name in ["wineserver", "game.exe", "unknown"]:
                (process / "comm").write_text(name)
                self.assertTrue(register.prefix_is_busy(self.prefix, proc))
            (process / "comm").unlink()
            self.assertTrue(register.prefix_is_busy(self.prefix, proc))

    def test_process_exiting_during_scan_is_ignored(self):
        proc = self.root / "proc"
        (proc / "123").mkdir(parents=True)
        with patch.object(Path, "read_bytes", side_effect=ProcessLookupError):
            self.assertFalse(register.prefix_is_busy(self.prefix, proc))

    def test_manager_discovery_is_authoritative(self):
        response = subprocess.CompletedProcess([], 0, json.dumps({"targets": [self.target, {"kind": "wine", "prefix": "/other"}]}))
        with patch.object(register.subprocess, "run", return_value=response):
            self.assertEqual(register.steam_targets(), {self.prefix: self.target})

    def test_activation_defers_runtime_download_and_unknown_runner(self):
        patch.object(register, "prefixes", return_value=[self.prefix]).start()
        patch.object(register, "PIPEASIO_REGISTER", self.source).start()
        patch.object(register, "prefix_is_busy", return_value=False).start()
        self.target["metadata"]["runtime_ready"] = False
        with patch.object(register, "steam_targets", return_value={self.prefix: self.target}), patch.object(register, "register_prefix") as run, patch("sys.argv", ["register", "--skip-registered", "--no-runtime-download"]):
            self.assertEqual(register.main(), 0)
            run.assert_not_called()
        with patch.object(register, "steam_targets", return_value={}), patch.object(register, "register_prefix") as run, patch("sys.argv", ["register"]):
            self.assertEqual(register.main(), 0)
            run.assert_not_called()
        self.target["metadata"]["runtime_ready"] = True
        with patch.object(register, "steam_targets", return_value={self.prefix: self.target}), patch.object(register, "register_prefix", return_value=True) as run, patch("sys.argv", ["register", "--skip-registered"]):
            self.assertEqual(register.main(), 0)
            run.assert_called_once_with(self.prefix, self.target)


if __name__ == "__main__":
    unittest.main()
