{
  pi-coding-agent,
  fetchFromGitHub,
  fetchurl,
  fetchNpmDeps,
}:
# Remove this override once the pinned nixpkgs provides Pi >= 1.3.0.
pi-coding-agent.overrideAttrs (
  finalAttrs: previousAttrs: {
    version = "1.3.0";

    src = fetchFromGitHub {
      owner = "earendil-works";
      repo = "pi";
      tag = "v${finalAttrs.version}";
      hash = "sha256-AsutbwnjiwwLkB5tqLW+1GdGZyLmXsU0W+SNdNhJu7U=";
    };

    npmDepsHash = "sha256-+gFyvrhkCsF99oNvs0gBmLXnDW0hWnZI/wFId7UbI6Q=";
    npmDeps = fetchNpmDeps {
      name = "pi-coding-agent-${finalAttrs.version}-npm-deps";
      inherit (finalAttrs) src;
      hash = finalAttrs.npmDepsHash;
    };

    modelData = fetchurl {
      url = "https://registry.npmjs.org/@earendil-works/pi-ai/-/pi-ai-${finalAttrs.version}.tgz";
      hash = "sha256-U0PhY5vzQ73DNE3zrWwxwFpQtoutB6xrzhCJDUtrimE=";
    };

    buildPhase = ''
      runHook preBuild
      npm run build:offline
      runHook postBuild
    '';

    # The base recipe's workspace list follows its own Pi release, so replace it
    # with the runtime workspaces of this version instead of appending to it.
    postInstall = ''
      nm="$out/lib/node_modules/pi-monorepo/node_modules"
      for ws in chord:chord pi-ai:ai pi-agent-core:agent pi-codemode:codemode \
                pi-durable:durable pi-env:env pi-mcp:mcp pi-telemetry:telemetry pi-tui:tui; do
        IFS=: read -r pkg src <<< "$ws"
        rm "$nm/@earendil-works/$pkg"
        cp -r "packages/$src" "$nm/@earendil-works/$pkg"
      done
      find "$nm" -type l -lname '*/packages/*' -delete
      find "$nm/.bin" -xtype l -delete
    '';
    postInstallCheck = (previousAttrs.postInstallCheck or "") + ''
      (
        cd "$out/lib/node_modules/pi-monorepo"
        node --input-type=module -e 'await import("@earendil-works/pi-codemode/declarations"); await import("@earendil-works/pi-mcp");'
      )
    '';

    meta = previousAttrs.meta // {
      changelog = "https://github.com/earendil-works/pi/blob/v${finalAttrs.version}/packages/coding-agent/CHANGELOG.md";
    };
  }
)
