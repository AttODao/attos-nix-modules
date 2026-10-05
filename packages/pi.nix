{
  pi-coding-agent,
  fetchFromGitHub,
  fetchurl,
  fetchNpmDeps,
}:
# Remove this override once the pinned nixpkgs provides Pi >= 1.0.2.
pi-coding-agent.overrideAttrs (
  finalAttrs: previousAttrs: {
    version = "1.0.2";

    src = fetchFromGitHub {
      owner = "earendil-works";
      repo = "pi";
      tag = "v${finalAttrs.version}";
      hash = "sha256-DjWJE7KcCdNF/M3RrO76rKCSd6oFLo2dX9wFT0nwEXk=";
    };

    npmDepsHash = "sha256-gW0JO84SrPl3PDUu7eBzOKaNGSif23J1xY1tpS/oVhQ=";
    npmDeps = fetchNpmDeps {
      name = "pi-coding-agent-${finalAttrs.version}-npm-deps";
      inherit (finalAttrs) src;
      hash = finalAttrs.npmDepsHash;
    };

    modelData = fetchurl {
      url = "https://registry.npmjs.org/@earendil-works/pi-ai/-/pi-ai-${finalAttrs.version}.tgz";
      hash = "sha256-isjl+r1l4PDsuFOLYhGCSFn1mXWUAF16A+H3CzhDihc=";
    };

    buildPhase = ''
      runHook preBuild
      npm run build:offline
      runHook postBuild
    '';

    meta = previousAttrs.meta // {
      changelog = "https://github.com/earendil-works/pi/blob/v${finalAttrs.version}/packages/coding-agent/CHANGELOG.md";
    };
  }
)
