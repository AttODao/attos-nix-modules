#!@PYTHON@
from __future__ import annotations

import configparser
import json
import os
import shutil
import subprocess
import sys
import tempfile
import tomllib
import urllib.error
import urllib.request
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from zipfile import BadZipFile, ZipFile


APP_NAME = "pandora-github-mods"
CONFIG_VERSION = 1
GITHUB_API_VERSION = "2022-11-28"
CONFIG_ROOT_ENV = "PANDORA_GITHUB_MODS_CONFIG_DIR"
INSTANCE_ROOT_ENV = "PANDORA_LAUNCHER_INSTANCES_DIR"

LOADER_MAP = {
    "net.fabricmc.fabric-loader": "fabric",
    "net.minecraftforge": "forge",
    "net.neoforged": "neo-forge",
    "org.quiltmc.quilt-loader": "quilt",
}
LOADER_TOKENS = {
    "fabric": ("fabric",),
    "forge": ("forge",),
    "neo-forge": ("neoforge", "neo-forge"),
    "quilt": ("quilt",),
}


class AppError(Exception):
    def __init__(self, message: str, code: int = 1, show_usage: bool = False) -> None:
        super().__init__(message)
        self.code = code
        self.show_usage = show_usage


@dataclass(slots=True)
class Instance:
    directory: Path
    name: str
    game_version: str
    loader: str
    minecraft_subdir: str = "minecraft"

    @property
    def mods_dir(self) -> Path:
        return self.directory / self.minecraft_subdir / "mods"


@dataclass(slots=True)
class ModRecord:
    repo: str
    display_name: str | None = None
    mod_id: str | None = None
    asset_name: str | None = None
    version: str | None = None

    @property
    def owner(self) -> str:
        return self.repo.split("/", 1)[0]

    @property
    def project(self) -> str:
        return self.repo.split("/", 1)[1]

    @property
    def slug(self) -> str:
        return self.project

    @classmethod
    def from_config(cls, value: object) -> ModRecord | None:
        if not isinstance(value, dict):
            return None
        repo = as_text(value.get("repo"))
        if repo is None:
            return None
        return cls(
            repo=normalize_repo_spec(repo),
            display_name=as_text(value.get("display_name")),
            mod_id=as_text(value.get("mod_id")),
            asset_name=as_text(value.get("asset_name")),
            version=normalize_version(as_text(value.get("version"))),
        )

    def to_config(self) -> dict[str, str]:
        data = {"repo": self.repo}
        for key in ("display_name", "mod_id", "asset_name", "version"):
            value = getattr(self, key)
            if value:
                data[key] = value
        return data

    def matches(self, selector: str) -> bool:
        value = selector.strip().lower()
        candidates = {
            self.repo.lower(),
            self.slug.lower(),
            self.display_name.lower() if self.display_name else "",
            self.mod_id.lower() if self.mod_id else "",
            self.asset_name.lower() if self.asset_name else "",
        }
        return value in candidates


@dataclass(slots=True)
class Profile:
    config_file: Path
    mods: list[ModRecord]

    @classmethod
    def load(cls, instance: Instance) -> Profile:
        config_file = profile_config_file(instance.directory)
        if config_file.is_file():
            return cls(config_file, load_mods_config(config_file))

        profile = cls(config_file, [])
        profile.save()
        return profile

    def save(self) -> None:
        data = {
            "version": CONFIG_VERSION,
            "mods": [record.to_config() for record in self.mods],
        }
        write_json(self.config_file, data)

    def find(self, selector: str) -> ModRecord | None:
        return next((record for record in self.mods if record.matches(selector)), None)

    def selected(self, selectors: list[str]) -> list[ModRecord]:
        if not selectors:
            return list(self.mods)

        selected: list[ModRecord] = []
        for selector in selectors:
            record = self.find(selector)
            if record is None:
                raise AppError(f"Unknown GitHub mod: {selector}")
            if all(existing.repo != record.repo for existing in selected):
                selected.append(record)
        return selected

    def add(self, record: ModRecord) -> ModRecord:
        existing = next((mod for mod in self.mods if mod.repo == record.repo), None)
        if existing is not None:
            return existing
        self.mods.append(record)
        return record

    def remove(self, selector: str) -> None:
        before = len(self.mods)
        self.mods = [record for record in self.mods if not record.matches(selector)]
        if len(self.mods) == before:
            raise AppError(f"Unknown GitHub mod: {selector}")


@dataclass(slots=True)
class ReleaseAsset:
    name: str
    url: str


@dataclass(slots=True)
class Release:
    version: str
    assets: list[ReleaseAsset]


class GitHubClient:
    def latest_release(self, record: ModRecord) -> Release:
        data = self.request_json(
            f"https://api.github.com/repos/{record.owner}/{record.project}/releases/latest"
        )
        version = normalize_version(as_text(data.get("tag_name")))
        if version is None:
            raise AppError(f"Could not determine latest release version for {record.repo}")

        assets: list[ReleaseAsset] = []
        raw_assets = data.get("assets", [])
        if isinstance(raw_assets, list):
            for raw_asset in raw_assets:
                if not isinstance(raw_asset, dict):
                    continue
                name = as_text(raw_asset.get("name"))
                url = as_text(raw_asset.get("browser_download_url"))
                if name and url:
                    assets.append(ReleaseAsset(name, url))

        return Release(version, assets)

    def request_json(self, url: str) -> dict[str, object]:
        request = urllib.request.Request(url, headers=github_headers())
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.loads(response.read().decode("utf-8"))

    def download(self, url: str, destination: Path) -> None:
        request = urllib.request.Request(url, headers={"User-Agent": APP_NAME})
        token = github_token()
        if token:
            request.add_header("Authorization", f"Bearer {token}")

        with urllib.request.urlopen(request, timeout=60) as response, destination.open("wb") as handle:
            shutil.copyfileobj(response, handle)


class JarIndex:
    def __init__(self, mods_dir: Path) -> None:
        self.mods_dir = mods_dir
        self._metadata: dict[Path, tuple[str | None, str | None]] = {}

    def metadata(self, jar: Path) -> tuple[str | None, str | None]:
        if jar not in self._metadata:
            self._metadata[jar] = read_jar_metadata(jar)
        return self._metadata[jar]

    def matching(self, record: ModRecord) -> list[Path]:
        slug = record.slug.lower()
        mod_id = record.mod_id.lower() if record.mod_id else None
        asset_name = record.asset_name.lower() if record.asset_name else None

        matches: list[Path] = []
        for jar in self.mods_dir.glob("*.jar"):
            jar_slug = jar.stem.lower()
            metadata_id, _ = self.metadata(jar)
            metadata_id_lower = metadata_id.lower() if metadata_id else None
            if not (
                slug in jar_slug
                or (mod_id is not None and metadata_id_lower == mod_id)
                or (asset_name is not None and jar.name.lower() == asset_name)
            ):
                continue
            matches.append(jar)
        return matches

    def current_version(self, record: ModRecord) -> str | None:
        matches = self.matching(record)
        if not matches:
            return None

        matched_versions = {self.metadata(jar)[1] for jar in matches}
        non_null_versions = {version for version in matched_versions if version is not None}
        if len(non_null_versions) == 1:
            return next(iter(non_null_versions))
        return record.version


class ModManager:
    def __init__(self, instance: Instance, github: GitHubClient) -> None:
        self.instance = instance
        self.github = github
        self.jars = JarIndex(instance.mods_dir)

    def install_or_update(self, record: ModRecord) -> str | None:
        release = self.github.latest_release(record)
        installed = self.jars.matching(record)
        if record.version == release.version and installed:
            return None

        asset = self.pick_asset(record, release)
        destination = self.instance.mods_dir / asset.name
        self.download_asset(asset, destination)
        for old_jar in installed:
            if old_jar != destination:
                old_jar.unlink()
        record.asset_name = asset.name
        record.version = release.version
        self.jars = JarIndex(self.instance.mods_dir)
        return release.version

    def pick_asset(self, record: ModRecord, release: Release) -> ReleaseAsset:
        jar_assets = [asset for asset in release.assets if asset.name.lower().endswith(".jar")]
        if not jar_assets:
            raise AppError(f"No jar asset found for {record.repo} v{release.version}")

        def loader_matches(name: str) -> bool:
            if self.instance.loader == "forge":
                return "forge" in name and "neoforge" not in name and "neo-forge" not in name
            return any(token in name for token in LOADER_TOKENS[self.instance.loader])

        # Releases often contain one JAR per loader and Minecraft version; rank both
        # dimensions and fail instead of installing an arbitrary tied asset.
        def score(asset: ReleaseAsset) -> tuple[int, int, int]:
            name = asset.name.lower()
            return (
                int(loader_matches(name)),
                int(self.instance.game_version.lower() in name),
                int(record.project.lower() in name or record.slug.lower() in name),
            )

        best_score = max(score(asset) for asset in jar_assets)
        best_assets = [asset for asset in jar_assets if score(asset) == best_score]
        if len(best_assets) != 1:
            names = ", ".join(asset.name for asset in best_assets)
            raise AppError(
                f"Ambiguous jar assets for {record.repo} v{release.version}: {names}"
            )
        return best_assets[0]

    def download_asset(self, asset: ReleaseAsset, destination: Path) -> None:
        destination.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(
            dir=destination.parent,
            prefix=f".{destination.stem}.",
            suffix=".download",
            delete=False,
        ) as handle:
            temp_path = Path(handle.name)

        try:
            self.github.download(asset.url, temp_path)
            temp_path.replace(destination)
        finally:
            temp_path.unlink(missing_ok=True)


def xdg_data_home() -> Path:
    return Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local" / "share")).expanduser()


def xdg_config_home() -> Path:
    return Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")).expanduser()


def instances_root() -> Path:
    override = os.environ.get(INSTANCE_ROOT_ENV)
    if override:
        return Path(override).expanduser()
    return xdg_data_home() / "PandoraLauncher" / "instances"


def config_root() -> Path:
    override = os.environ.get(CONFIG_ROOT_ENV)
    if override:
        return Path(override).expanduser()
    return xdg_config_home() / APP_NAME


def profile_config_file(instance_dir: Path) -> Path:
    return config_root() / instance_dir.name / "config.json"


def read_json(path: Path) -> dict[str, object]:
    try:
        return json.loads(path.read_text())
    except FileNotFoundError as exc:
        raise AppError(f"Missing config: {path}") from exc
    except json.JSONDecodeError as exc:
        raise AppError(f"Invalid JSON config: {path}") from exc


def write_json(path: Path, data: dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")


def as_text(value: object | None) -> str | None:
    if isinstance(value, str):
        value = value.strip()
        return value or None
    return None


def normalize_version(value: str | None) -> str | None:
    if value is None:
        return None
    version = value.strip()
    if version.lower().startswith("v"):
        version = version[1:]
    return version or None


def normalize_repo_spec(value: str) -> str:
    repo = value.strip()
    if repo.startswith("https://github.com/"):
        repo = repo.removeprefix("https://github.com/")
    elif repo.startswith("http://github.com/"):
        repo = repo.removeprefix("http://github.com/")
    elif repo.startswith("github.com/"):
        repo = repo.removeprefix("github.com/")
    repo = repo.strip("/")
    if repo.count("/") != 1:
        raise AppError(f"Expected GitHub repository in owner/name form, got: {value}")
    owner, name = repo.split("/", 1)
    if not owner or not name:
        raise AppError(f"Expected GitHub repository in owner/name form, got: {value}")
    return f"{owner}/{name}"


def load_mods_config(config_file: Path) -> list[ModRecord]:
    raw_mods = read_json(config_file).get("mods", [])
    if not isinstance(raw_mods, list):
        raise AppError("Invalid config: mods must be a list")

    return [record for raw in raw_mods if (record := ModRecord.from_config(raw)) is not None]


@lru_cache(maxsize=1)
def github_token() -> str | None:
    for env_var in ("GITHUB_TOKEN", "GH_TOKEN"):
        token = os.environ.get(env_var)
        if token:
            return token

    if not shutil.which("gh"):
        return None

    result = subprocess.run(
        ["gh", "auth", "token"],
        check=False,
        text=True,
        capture_output=True,
    )
    if result.returncode != 0:
        return None

    return result.stdout.strip() or None


def github_headers() -> dict[str, str]:
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": APP_NAME,
        "X-GitHub-Api-Version": GITHUB_API_VERSION,
    }
    token = github_token()
    if token:
        headers["Authorization"] = f"Bearer {token}"
    return headers


def read_jar_metadata(jar_path: Path) -> tuple[str | None, str | None]:
    try:
        with ZipFile(jar_path) as archive:
            names = set(archive.namelist())

            if "fabric.mod.json" in names:
                data = json.loads(archive.read("fabric.mod.json").decode("utf-8"))
                return as_text(data.get("id")), normalize_version(as_text(data.get("version")))

            if "quilt.mod.json" in names:
                data = json.loads(archive.read("quilt.mod.json").decode("utf-8"))
                loader = data.get("quilt_loader", {})
                if isinstance(loader, dict):
                    return as_text(loader.get("id")), normalize_version(as_text(loader.get("version")))
                return as_text(data.get("id")), normalize_version(as_text(data.get("version")))

            for manifest_name in ("META-INF/mods.toml", "META-INF/neoforge.mods.toml"):
                if manifest_name not in names:
                    continue
                data = tomllib.loads(archive.read(manifest_name).decode("utf-8"))
                mods = data.get("mods", [])
                if isinstance(mods, list) and mods and isinstance(mods[0], dict):
                    first = mods[0]
                    return (
                        as_text(first.get("modId") or first.get("modid")),
                        normalize_version(as_text(first.get("version"))),
                    )
    except (BadZipFile, KeyError, json.JSONDecodeError, UnicodeDecodeError, tomllib.TOMLDecodeError, OSError):
        return None, None

    return None, None


def resolve_instance(identifier: str) -> Path:
    path = Path(identifier).expanduser()
    if is_instance_directory(path):
        return path

    candidate = instances_root() / identifier
    if is_instance_directory(candidate):
        return candidate

    known = sorted(
        p.name
        for p in instances_root().iterdir()
        if is_instance_directory(p)
    ) if instances_root().is_dir() else []

    if known:
        suffix = "\nKnown instances:\n" + "\n".join(f"  - {name}" for name in known)
    else:
        suffix = ""
    raise AppError(f"Unknown Pandora instance: {identifier}{suffix}", 2)


def is_instance_directory(path: Path) -> bool:
    return path.is_dir() and any(
        (path / marker).is_file() for marker in ("instance.cfg", "info_v1.json")
    )


def read_instance(identifier: str) -> Instance:
    instance_dir = resolve_instance(identifier)
    cfg_path = instance_dir / "instance.cfg"

    if not cfg_path.is_file():
        return read_pandora_instance(instance_dir)

    return read_legacy_instance(instance_dir)


def read_legacy_instance(instance_dir: Path) -> Instance:
    cfg_path = instance_dir / "instance.cfg"
    pack_path = instance_dir / "mmc-pack.json"

    parser = configparser.ConfigParser(interpolation=None)
    if not parser.read(cfg_path):
        raise AppError(f"Unable to read Pandora config: {cfg_path}")

    try:
        name = parser.get("General", "name")
    except (configparser.NoSectionError, configparser.NoOptionError):
        name = instance_dir.name

    try:
        pack = json.loads(pack_path.read_text())
    except FileNotFoundError as exc:
        raise AppError(f"Missing Pandora pack metadata: {pack_path}") from exc
    except json.JSONDecodeError as exc:
        raise AppError(f"Invalid Pandora pack metadata: {pack_path}") from exc

    components = pack.get("components", [])
    if not isinstance(components, list):
        raise AppError(f"Invalid Pandora pack metadata: {pack_path}")

    game_version = next(
        (
            component.get("version")
            for component in components
            if isinstance(component, dict) and component.get("uid") == "net.minecraft"
        ),
        None,
    )
    if not isinstance(game_version, str):
        raise AppError(f"Could not determine Minecraft version from {pack_path}")

    loader = next(
        (
            mapped
            for uid, mapped in LOADER_MAP.items()
            if any(isinstance(component, dict) and component.get("uid") == uid for component in components)
        ),
        None,
    )
    if loader is None:
        raise AppError(f"Could not determine mod loader from {pack_path}")

    return Instance(instance_dir, name, game_version, loader)


def read_pandora_instance(instance_dir: Path) -> Instance:
    info_path = instance_dir / "info_v1.json"
    info = read_json(info_path)

    game_version = as_text(info.get("minecraft_version"))
    if game_version is None:
        raise AppError(f"Could not determine Minecraft version from {info_path}")

    loader_value = as_text(info.get("loader"))
    loader = normalize_loader(loader_value)
    if loader is None:
        if loader_value is None:
            raise AppError(f"Could not determine mod loader from {info_path}")
        raise AppError(f"Unsupported mod loader {loader_value!r} in {info_path}")

    name = as_text(info.get("name")) or instance_dir.name
    return Instance(instance_dir, name, game_version, loader, ".minecraft")


def normalize_loader(value: str | None) -> str | None:
    if value is None:
        return None
    loader = value.strip().lower().replace("_", "-")
    if loader == "neoforge":
        loader = "neo-forge"
    return loader if loader in LOADER_TOKENS else None


def usage(argv0: str) -> None:
    command = Path(argv0).name
    print(
        f"Usage: {command} <pandora-instance> [list|add|remove|upgrade] ...\n"
        "Examples:\n"
        f"  {command} mob_life upgrade\n"
        f"  {command} mob_life add AttODao/mob_life",
        file=sys.stderr,
    )


def command_list(profile: Profile, manager: ModManager) -> int:
    if not profile.mods:
        print("No GitHub release mods configured.")
        return 0

    for record in profile.mods:
        current = manager.jars.current_version(record) or "missing"
        tracked = record.version or "unknown"
        asset = record.asset_name or "-"
        print(f"{record.repo}: installed={current} tracked={tracked} asset={asset}")
    return 0


def command_add(profile: Profile, manager: ModManager, args: list[str]) -> int:
    if not args:
        raise AppError("Missing GitHub repository argument", 2, True)

    record = profile.add(ModRecord(normalize_repo_spec(args[0])))
    try:
        version = manager.install_or_update(record)
    except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError) as exc:
        raise AppError(f"Failed to add {record.repo}: {exc}") from exc

    profile.save()
    if version:
        print(f"Added GitHub release mod: {record.repo} -> {version}", file=sys.stderr)
    else:
        print(f"Added GitHub release mod: {record.repo}", file=sys.stderr)
    return 0


def command_remove(profile: Profile, args: list[str]) -> int:
    if not args:
        raise AppError("Missing mod selector", 2, True)

    profile.remove(args[0])
    profile.save()
    print(f"Removed GitHub release mod: {args[0]}", file=sys.stderr)
    return 0


def command_upgrade(profile: Profile, manager: ModManager, args: list[str]) -> int:
    records = profile.selected(args)
    if not records:
        print("No GitHub release mods configured.", file=sys.stderr)
        return 0

    updated: list[str] = []
    failures: list[str] = []

    for record in records:
        try:
            version = manager.install_or_update(record)
        except (AppError, urllib.error.HTTPError, urllib.error.URLError, TimeoutError) as exc:
            failures.append(record.repo)
            print(f"Failed to update {record.repo}: {exc}", file=sys.stderr)
            continue

        if version is not None:
            updated.append(f"{record.repo} -> {version}")

    profile.save()
    if updated:
        print("Updated GitHub release mods: " + ", ".join(updated), file=sys.stderr)
    if failures:
        return 1
    if not updated:
        print("All up to date!", file=sys.stderr)
    return 0


def run(argv: list[str]) -> int:
    if len(argv) < 2:
        usage(argv[0])
        return 2

    instance = read_instance(argv[1])
    instance.mods_dir.mkdir(parents=True, exist_ok=True)
    profile = Profile.load(instance)
    manager = ModManager(instance, GitHubClient())

    command = argv[2] if len(argv) > 2 else "list"
    args = argv[3:]

    if command in {"list", "ls", "status", "info"}:
        return command_list(profile, manager)
    if command == "add":
        return command_add(profile, manager, args)
    if command == "remove":
        return command_remove(profile, args)
    if command == "upgrade":
        return command_upgrade(profile, manager, args)

    usage(argv[0])
    return 2


def main(argv: list[str]) -> int:
    try:
        return run(argv)
    except AppError as exc:
        print(exc, file=sys.stderr)
        if exc.show_usage:
            usage(argv[0])
        return exc.code


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
