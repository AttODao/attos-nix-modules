{
  lib,
  stdenv,
  buildNpmPackage,
  fetchurl,
  nodejs_22,
  libuv,
  makeWrapper,
  autoPatchelfHook,
}:

buildNpmPackage {
  pname = "paseo";
  version = "0.12.0";

  # Raw archive hash, not the unpacked hash expected by fetchFromGitHub.
  src = fetchurl {
    url = "https://codeload.github.com/getpaseo/paseo/tar.gz/cafe4b01c8522ff39560241c5deb01427dc8dc5b";
    name = "paseo-0.12.0.tar.gz";
    hash = "sha256-hnEoqSOmlaCGTdRKanNDv6FQ9T5oHu+rVcirGm7uVoo=";
  };

  nodejs = nodejs_22;

  # Prefetched from the unchanged upstream root lockfile with the pinned
  # nixpkgs prefetch-npm-deps tool, NPM_FETCHER_VERSION=2 (workspace metadata).
  npmDepsFetcherVersion = 2;
  npmDepsHash = "sha256-fUFbCuBtOe67+n3eatRP50OOZBydjsGHxHV0q4pT5wA=";
  npmBuildScript = "build:server";

  # Keep the locked monorepo installation, but run only the necessary native
  # lifecycle scripts: no Electron/browser downloads or lefthook preparation.
  npmRebuildFlags = [
    "node-pty"
    "esbuild"
  ];
  env.npm_config_build_from_source = "true";

  nativeBuildInputs = [
    makeWrapper
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [
    libuv
    stdenv.cc.cc.lib
  ];

  postPatch = ''
    # nft cannot reliably infer every computed platform-package lookup. Retain
    # the complete host Claude SDK executable and server esbuild packages.
    # Sherpa's host addon, libraries and assets are already explicit upstream.
    substituteInPlace scripts/trace-daemon.mjs --replace-fail \
      'const additionalInputs = [' \
      'const additionalInputs = [
        resolvedPackageFiles("packages/server/dist/server/server/agent/providers/claude/agent.js", `@anthropic-ai/claude-agent-sdk-''${process.platform}-''${process.arch}`),
        resolvedPackageFiles("packages/server/dist/server/server/plugins/compiler.js", "esbuild"),
        resolvedPackageFiles("packages/server/dist/server/server/plugins/compiler.js", `@esbuild/''${process.platform}-''${process.arch}`),'
  '';

  preBuild = ''
    # npm rebuild above intentionally skips the root postinstall. Its SDK
    # patches still apply; Git-hook preparation is not needed in a derivation.
    PATH="$PWD/node_modules/.bin:$PATH" node scripts/postinstall-patches.mjs
  '';

  installPhase = ''
    runHook preInstall

    # Reuse upstream's runtime trace, including worker entrypoints and assets.
    # Copy with symlinks intact and preserve the monorepo-relative layout.
    node scripts/trace-daemon.mjs > daemon-files.txt
    mkdir -p "$out/lib/paseo"
    while IFS= read -r path; do
      [ -n "$path" ] || continue
      # glob() also emits directories; copy only files and symlinks.
      if [ -d "$path" ] && [ ! -L "$path" ]; then continue; fi
      mkdir -p "$out/lib/paseo/$(dirname "$path")"
      cp -a "$path" "$out/lib/paseo/$path"
    done < daemon-files.txt
    cp package.json LICENSE "$out/lib/paseo/"

    # Shell integration also calls the retained CLI bin directly.
    patchShebangs --build "$out/lib/paseo"
    mkdir -p "$out/bin"
    makeWrapper ${nodejs_22}/bin/node "$out/bin/paseo" \
      --add-flags "--disable-warning=DEP0040 $out/lib/paseo/packages/cli/dist/index.js"

    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    HOME=$(mktemp -d) "$out/bin/paseo" --help >/dev/null
  '';

  meta = {
    description = "Paseo CLI and coding-agent daemon (without bundled web UI)";
    homepage = "https://paseo.sh";
    changelog = "https://github.com/getpaseo/paseo/releases/tag/v0.12.0";
    license = lib.licenses.asl20;
    mainProgram = "paseo";
    # The speech runtime has locked native packages for these platforms.
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
  };
}
