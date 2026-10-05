{
  context-mode,
  fetchurl,
  fetchzip,
  linkFarm,
}:
let
  # The upstream bundles leave HTML conversion dependencies external.
  htmlDependencies = linkFarm "context-mode-html-dependencies" [
    {
      name = "turndown";
      path = fetchzip {
        url = "https://registry.npmjs.org/turndown/-/turndown-7.2.4.tgz";
        hash = "sha256-0yuqO/oT9Hgv9+3bdISnPekLKQ0/KQ/5W+00AePPHek=";
      };
    }
    {
      name = "turndown-plugin-gfm";
      path = fetchzip {
        url = "https://registry.npmjs.org/turndown-plugin-gfm/-/turndown-plugin-gfm-1.0.2.tgz";
        hash = "sha256-qmYSNSElreIMloq+s/FfsGRGeGUnoNplDYsTfXB5G5I=";
      };
    }
    {
      name = "@mixmark-io/domino";
      path = fetchzip {
        url = "https://registry.npmjs.org/@mixmark-io/domino/-/domino-2.2.0.tgz";
        hash = "sha256-McHC7TFuRR2WPgIXcrN2t9//+DexvCFqXpxgbKdWdVU=";
      };
    }
  ];
in
# Remove the override once nixpkgs ships this version and its Pi adapter/dependencies.
context-mode.overrideAttrs (
  finalAttrs: previousAttrs: {
    version = "1.0.169";
    # Pi loads skills from the package manifest; generic discovery finds duplicate copies.
    dontInstallAgentSkills = true;
    src = fetchurl {
      url = "https://registry.npmjs.org/context-mode/-/context-mode-${finalAttrs.version}.tgz";
      hash = "sha256-CcQeTPd7IVZsdrjqL9vX89gjBV/uLwLCFm/Vu1ddryw=";
    };
    # Include the Pi adapter and expose the CLI (which also starts MCP with no arguments).
    installPhase =
      builtins.replaceStrings
        [ "insight" "$out/lib/context-mode/server.bundle.mjs" ]
        [ "build" "$out/lib/context-mode/cli.bundle.mjs" ]
        previousAttrs.installPhase;
    postInstall = (previousAttrs.postInstall or "") + ''
      cp -rL ${htmlDependencies} $out/lib/context-mode/node_modules
    '';
  }
)
