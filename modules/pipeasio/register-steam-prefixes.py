#!/usr/bin/env @PYTHON@
from __future__ import annotations

import argparse
import filecmp
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


PIPEASIO_REGISTER = Path("@PIPEASIO_REGISTER@")
MANAGER = Path("@MANAGER@")
UMU = Path("@UMU@")
PROTON_RUN = Path("@PROTON_RUN@")
DRIVER_DLL = Path("@DRIVER_DLL@")
PIPEASIO_REGISTRY_CLSID = "{2D3CA9E2-1193-4C5D-B5FD-38798F3DC074}"
DEFAULT_STEAM_ROOTS = [
    Path.home() / ".local/share/Steam",
    Path.home() / ".steam/steam",
    Path.home() / ".var/app/com.valvesoftware.Steam/data/Steam",
]


def eprint(message: str) -> None:
    print(message, file=sys.stderr)


def canonical(path: Path) -> Path:
    return path.expanduser().resolve(strict=False)


def parse_library_folders(vdf: Path) -> list[Path]:
    try:
        text = vdf.read_text(encoding="utf-8", errors="replace")
    except OSError as exc:
        eprint(f"pipeasio: could not read {vdf}: {exc}")
        return []

    libraries: list[Path] = []
    for match in re.finditer(r'^\s*"path"\s+"([^"]+)"', text, re.MULTILINE):
        libraries.append(Path(match.group(1)))
    return libraries


def steam_roots() -> list[Path]:
    raw_roots = list(DEFAULT_STEAM_ROOTS)
    extra_roots = os.environ.get("STEAM_ROOTS", "")
    if extra_roots:
        raw_roots.extend(Path(item) for item in extra_roots.split(os.pathsep) if item)

    roots: list[Path] = []
    seen: set[Path] = set()
    for root in raw_roots:
        root = canonical(root)
        if root in seen:
            continue
        seen.add(root)
        roots.append(root)
    return roots


def library_paths() -> list[Path]:
    libraries: list[Path] = []
    seen: set[Path] = set()

    for steam_root in steam_roots():
        candidates = [steam_root]
        vdf = steam_root / "steamapps" / "libraryfolders.vdf"
        if vdf.is_file():
            candidates.extend(parse_library_folders(vdf))

        for path in candidates:
            path = canonical(path)
            if path in seen:
                continue
            seen.add(path)
            compatdata = path / "steamapps" / "compatdata"
            if compatdata.is_dir():
                libraries.append(path)

    return libraries


def prefixes() -> list[Path]:
    found: list[Path] = []
    seen: set[Path] = set()

    for library in library_paths():
        compatdata = library / "steamapps" / "compatdata"
        for appdir in sorted(compatdata.iterdir(), key=lambda path: path.name):
            if not appdir.is_dir() or not appdir.name.isdigit():
                continue
            prefix = canonical(appdir / "pfx")
            if not prefix.is_dir() or prefix in seen:
                continue
            seen.add(prefix)
            found.append(prefix)

    return found


def prefix_is_current(prefix: Path) -> bool:
    # Reading Wine's text registry avoids starting (and migrating) a prefix.
    try:
        registry = (prefix / "system.reg").read_text(encoding="utf-8", errors="replace")
        section = re.search(
            r'^\[Software\\\\ASIO\\\\PipeASIO\][^\n]*\n([^\[]*)',
            registry,
            re.MULTILINE | re.IGNORECASE,
        )
        return bool(
            section
            and re.search(
                r'^"CLSID"="' + re.escape(PIPEASIO_REGISTRY_CLSID) + r'"$',
                section[1],
                re.MULTILINE | re.IGNORECASE,
            )
            and filecmp.cmp(
                DRIVER_DLL, prefix / "drive_c/windows/system32/pipeasio64.dll", shallow=False
            )
        )
    except OSError:
        return False


def steam_targets() -> dict[Path, dict]:
    # Upstream resolves explicit compatibility choices before config_info's runner.
    env = os.environ.copy()
    env["PATH"] = f"{UMU.parent}:{env.get('PATH', '')}"
    result = subprocess.run(
        [str(MANAGER), "list"], env=env, check=True, capture_output=True, text=True
    )
    return {
        canonical(Path(target["prefix"])): target
        for target in json.loads(result.stdout)["targets"]
        if target.get("kind") == "steam" and target.get("prefix")
    }


def prefix_is_busy(prefix: Path, proc: Path = Path("/proc")) -> bool:
    for process in proc.iterdir():
        if not process.name.isdigit():
            continue
        try:
            if process.stat().st_uid != os.getuid():
                continue
            environment = (process / "environ").read_bytes().split(b"\0")
            for entry in environment:
                if entry.startswith(b"WINEPREFIX=") and canonical(
                    Path(os.fsdecode(entry[len(b"WINEPREFIX="):]))
                ) == prefix:
                    return True
        except (FileNotFoundError, ProcessLookupError):
            continue
        except PermissionError:
            # ponytail: allow known native session daemons; unknown unreadable processes still block.
            try:
                if (process / "comm").read_text().strip() in {
                    "systemd", "(sd-pam)", "Hyprland", ".Hyprland-wrapp", "ssh-agent",
                }:
                    continue
            except OSError:
                pass
            return True
    return False


def register_prefix(prefix: Path, target: dict) -> bool:
    eprint(f"pipeasio: registering {prefix} through {target['runner']}")
    env = os.environ.copy()
    # Never inherit another game's Proton settings or bypass the upstream guard.
    for key in list(env):
        if key.startswith(("STEAM_COMPAT_", "UMU_", "PROTON")) or key in {
            "WINEARCH", "WINEDLLOVERRIDES", "WINEDLLPATH", "WINELOADER", "WINESERVER",
            "PIPEASIO_REGISTER_WITHOUT_LOADING",
        }:
            del env[key]
    env.update(
        WINEPREFIX=str(prefix),
        WINE=str(PROTON_RUN),
        STEAM_COMPAT_DATA_PATH=str(prefix.parent),
        PROTONPATH=target["runner"],
        GAMEID="umu-0",
        PROTONFIXES_DISABLE="1",
        UMU_RUNTIME_UPDATE="0",
        PROTON_VERB="waitforexitandrun",
    )
    dll = prefix / "drive_c/windows/system32/pipeasio64.dll"
    backup = None
    backup_ready = False
    try:
        if prefix.stat().st_uid != os.getuid() or dll.is_symlink():
            raise OSError("prefix must belong to this user and driver must not be a symlink")
        if dll.exists():
            with tempfile.NamedTemporaryFile(prefix=".pipeasio-backup-", dir=dll.parent, delete=False) as file:
                backup = Path(file.name)
            shutil.copy2(dll, backup)
            backup_ready = True
        subprocess.run([str(PIPEASIO_REGISTER)], env=env, check=True)
    except (OSError, subprocess.CalledProcessError) as exc:
        if backup_ready:
            os.replace(backup, dll)
        eprint(f"pipeasio: failed to register {prefix}: {exc}")
        return False
    finally:
        if backup is not None:
            backup.unlink(missing_ok=True)
    return True


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Register PipeASIO in the Steam Proton prefixes on this system."
    )
    parser.add_argument(
        "--skip-registered",
        action="store_true",
        help="Skip prefixes whose registry and copied driver match this package.",
    )
    parser.add_argument(
        "--no-runtime-download",
        action="store_true",
        help="Defer prefixes whose umu Steam Runtime has not been downloaded yet.",
    )
    args = parser.parse_args()

    if not PIPEASIO_REGISTER.is_file():
        eprint(f"pipeasio: missing {PIPEASIO_REGISTER}")
        return 1

    steam_prefixes = prefixes()
    if not steam_prefixes:
        eprint("pipeasio: no existing Steam Proton prefixes found")
        return 0

    try:
        targets = steam_targets()
    except (OSError, subprocess.CalledProcessError, ValueError, KeyError) as exc:
        eprint(f"pipeasio: could not discover owning Proton runners: {exc}")
        return 1

    registered = 0
    failed = 0
    skipped = 0
    for prefix in steam_prefixes:
        if args.skip_registered and prefix_is_current(prefix):
            skipped += 1
            eprint(f"pipeasio: already registered in {prefix}, skipping")
            continue

        target = targets.get(prefix)
        reason = ""
        if not target:
            reason = "no installed Steam game/owning Proton found for this prefix"
        elif target.get("error") or not target.get("runner"):
            reason = target.get("error") or "owning Proton is not installed"
        elif args.no_runtime_download and not target.get("metadata", {}).get("runtime_ready"):
            reason = "run pipeasio-register-steam-prefixes manually to download the umu runtime"
        elif prefix_is_busy(prefix):
            reason = "close applications using this prefix, then rerun this command"
        if reason:
            skipped += 1
            eprint(f"pipeasio: deferred {prefix}: {reason}")
            continue

        if register_prefix(prefix, target):
            registered += 1
        else:
            failed += 1

    eprint(f"pipeasio: registered {registered} Steam prefixes")
    if skipped:
        eprint(f"pipeasio: skipped/deferred {skipped} prefix(es)")
    if failed:
        eprint(f"pipeasio: {failed} prefix(es) failed, see messages above")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
