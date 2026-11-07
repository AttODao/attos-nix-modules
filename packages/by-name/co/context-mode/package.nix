{
  pkgs,
  lib,
  fetchurl,
  makeWrapper,
  nodejs_24,
}:
# Remove the override once nixpkgs ships a 2.x version with the Pi adapter.
# scope内の同名attrでなく、利用ホストのbase packageを上書きする。
# 2.x publishes self-contained bundles (no npm dependencies) and uses node:sqlite
# (Node >= 24.15), so it runs on Node instead of the base package's Bun.
pkgs.context-mode.overrideAttrs (
  finalAttrs: previousAttrs: {
    version = "2.1.5";
    # Pi loads skills from the package manifest; generic discovery finds duplicate copies.
    dontInstallAgentSkills = true;
    src = fetchurl {
      url = "https://registry.npmjs.org/context-mode/-/context-mode-${finalAttrs.version}.tgz";
      hash = "sha256-qGaomacPe9WgKOW028dDC2ayJLVOpxjzwWcPSew8vbo=";
    };
    nativeBuildInputs = [ makeWrapper ];
    # Keep the whole published package: the CLI, the MCP server and the Pi adapter
    # (pi/index.js) find run.mjs, hooks and skills relative to themselves.
    installPhase = ''
      runHook preInstall

      mkdir -p $out/lib/context-mode $out/bin
      cp -r . $out/lib/context-mode/
      makeWrapper ${lib.getExe nodejs_24} $out/bin/context-mode \
        --add-flags "$out/lib/context-mode/cli.mjs" \
        --prefix PATH : ${lib.makeBinPath [ nodejs_24 ]}

      runHook postInstall
    '';
    # Fail on the next layout change instead of shipping a broken adapter or skill path.
    doInstallCheck = true;
    installCheckPhase = ''
      runHook preInstallCheck
      test -f $out/lib/context-mode/pi/index.js
      test -f $out/lib/context-mode/server.mjs
      for skill in ctx-doctor ctx-stats ctx-upgrade; do
        test -f $out/lib/context-mode/skills/$skill/SKILL.md
        test -f $out/lib/context-mode/pi/skills/$skill/SKILL.md
      done
      $out/bin/context-mode --version | grep -qF ${finalAttrs.version}
      runHook postInstallCheck
    '';
  }
)
