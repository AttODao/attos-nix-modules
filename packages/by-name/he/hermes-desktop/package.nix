# Hermes Desktopのremote専用build。upstreamのnix/desktop.nixを利用ホストのpkgsで呼び、
# local backend（Python venv）をclosureへ入れない。
{
  lib,
  callPackage,
  writeText,
  writeShellScriptBin,
  python3,
  npm-lockfile-fix,
  hermes-agent-src,
  extraRun ? [ ],
}:
let
  src = hermes-agent-src;
  version = "0.22.2";
  hermesNpmLib = callPackage "${src}/nix/lib.nix" { inherit npm-lockfile-fix; };
  # icon生成はPillowとresvg-pyだけを使う。
  generatedIcons = callPackage "${src}/nix/icons.nix" {
    venv = python3.withPackages (ps: [
      ps.pillow
      ps.resvg-py
    ]);
  };
  # payload = "light": runtimeを持たないremote専用artifact。
  installStampFile = writeText "hermes-install-stamp.json" (
    builtins.toJSON {
      schemaVersion = 2;
      commit = src.rev;
      commitDate = src.lastModified;
      branch = null;
      dirty = false;
      builtAt = null;
      baseVersion = version;
      displayVersion = version;
      distance = 0;
      source = "nix";
      distribution = "nix";
      pmRuntime = "";
      updateMechanism = "external";
      payload = "light";
      tag = null;
    }
  );
  # desktop.nixはHERMES_DESKTOP_HERMESへagentのpathを焼き込むため、空のstubを渡して起動時に外す。
  noBackend = writeShellScriptBin "hermes" ''
    echo "hermes-desktop: remote-only build without a local backend" >&2
    exit 1
  '';
in
callPackage "${src}/nix/desktop.nix" {
  inherit hermesNpmLib generatedIcons installStampFile;
  hermesAgent = noBackend;
  extraRun = [ "unset HERMES_DESKTOP_HERMES" ] ++ extraRun;
}
