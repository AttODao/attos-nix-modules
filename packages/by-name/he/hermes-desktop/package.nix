# Hermes Desktopのremote専用build。upstreamのnix/desktop.nixを利用ホストのpkgsで呼び、
# local backend（Python venv）をclosureへ入れない。
{
  lib,
  callPackage,
  writeText,
  writeShellScriptBin,
  python3,
  patchelfUnstable,
  hermes-agent-src,
  extraRun ? [ ],
}:
let
  src = hermes-agent-src;
  # Release tag of the hermes-agent flake input (packages/default.nix reads it from flake.lock).
  inherit (hermes-agent-src) version;
  # Upstream lib.nix builds with the node and pnpm pinned in pm/lock.json, as
  # upstream nix/packages.nix does. The pnpmDeps fixed-output hash
  # (nix/pnpm-deps-hash) is computed with that pnpm and node.
  # pm-packages.nix adds the header-overlap fix (NixOS/patchelf#672) to
  # `patchelf` with overrideAttrs. That patch is written for 0.19.2, the
  # `patchelf` of upstream's nixpkgs pin, and does not apply to the 0.15.2 of
  # the consumers' nixpkgs. patchelfUnstable already contains the fix, so it is
  # passed as is and the extra patch is dropped.
  patchelfFixed = patchelfUnstable // {
    overrideAttrs = _: patchelfUnstable;
  };
  pmPackages = lib.filterAttrs (_: lib.isDerivation) (
    callPackage "${src}/nix/pm-packages.nix" { patchelf = patchelfFixed; }
  );
  hermesNpmLib = callPackage "${src}/nix/lib.nix" { inherit pmPackages; };
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
(callPackage "${src}/nix/desktop.nix" {
  inherit hermesNpmLib generatedIcons installStampFile;
  hermesAgent = noBackend;
  extraRun = [ "unset HERMES_DESKTOP_HERMES" ] ++ extraRun;
}).overrideAttrs
  (previous: {
    # upstream nix/lib.nix reads the hermes-agent source during evaluation. Its
    # npm-based version failed under nix flake check --no-build, which is not
    # re-verified for the pnpm-based one; flake.nix keeps this package out of the
    # checked packages.
    passthru = (previous.passthru or { }) // {
      skipFlakeCheck = true;
    };
  })
