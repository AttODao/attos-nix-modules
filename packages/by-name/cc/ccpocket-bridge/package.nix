{
  lib,
  buildNpmPackage,
  fetchurl,
  nodejs_22,
  makeWrapper,
  patchelf,
}:

buildNpmPackage (finalAttrs: {
  pname = "ccpocket-bridge";
  version = "1.90.0";

  # Raw archive hash of the bridge/v1.90.0 tag, not the unpacked fetchFromGitHub hash.
  src = fetchurl {
    url = "https://codeload.github.com/K9i-0/ccpocket/tar.gz/f20a339dd100c5e0f60060340b171eb5315fd9f4";
    name = "ccpocket-${finalAttrs.version}.tar.gz";
    hash = "sha256-cMPCNy3v8QwWAuQbxuESQC6kdR88s3w7yzYO23MbswI=";
  };

  nodejs = nodejs_22;

  # Unchanged upstream root lockfile; NPM_FETCHER_VERSION=2 keeps workspace metadata.
  npmDepsFetcherVersion = 2;
  npmDepsHash = "sha256-hlSoJFPUmgI0YhY0t3bWCSW/DBr3fAVUj7Q5C39Fid8=";
  npmWorkspace = "packages/bridge";

  nativeBuildInputs = [
    makeWrapper
    patchelf
  ];

  installPhase = ''
    runHook preInstall

    # Production dependencies are hoisted to the root or kept in the workspace.
    npm prune --omit=dev --no-audit --no-fund --ignore-scripts
    # npm keeps musl prebuilds next to glibc ones; they cannot run on glibc.
    find node_modules packages/bridge/node_modules -maxdepth 2 -type d -name '*musl*' -prune \
      -exec rm -rf {} +

    lib=$out/lib/ccpocket
    mkdir -p $lib/packages/bridge
    cp -a node_modules package.json LICENSE $lib/
    cp -a packages/bridge/{dist,node_modules,package.json,LICENSE} $lib/packages/bridge/
    # Workspace self-links point back into the build directory.
    find $lib -xtype l -delete

    # The Claude Agent SDK runs its bundled Claude Code binary, which only
    # needs the loader. Do not autoPatchelf sharp: patched libvips segfaults,
    # and the unpatched addon finds libstdc++ already loaded by node.
    for claude in $lib/packages/bridge/node_modules/@anthropic-ai/claude-agent-sdk-linux-*/claude; do
      patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" "$claude"
    done

    makeWrapper ${nodejs_22}/bin/node $out/bin/ccpocket-bridge \
      --add-flags $lib/packages/bridge/dist/cli.js

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    export HOME=$(mktemp -d)
    $out/bin/ccpocket-bridge --version | grep -F ${finalAttrs.version}
    # Resolve sharp from the bridge package as the bridge itself does.
    (cd $out/lib/ccpocket/packages/bridge && ${nodejs_22}/bin/node -e "
      require('sharp')({ create: { width: 1, height: 1, channels: 3, background: 'red' } })
        .png().toBuffer().catch(() => process.exit(1));
    ")
    $out/lib/ccpocket/packages/bridge/node_modules/@anthropic-ai/claude-agent-sdk-linux-*/claude --version
  '';

  meta = {
    description = "CC Pocket Bridge Server for controlling Claude and Codex sessions from mobile";
    homepage = "https://github.com/K9i-0/ccpocket";
    changelog = "https://github.com/K9i-0/ccpocket/releases/tag/bridge/v${finalAttrs.version}";
    license = lib.licenses.mit;
    mainProgram = "ccpocket-bridge";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
})
