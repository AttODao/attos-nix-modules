{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  makeWrapper,
  nodejs,
}:

buildNpmPackage rec {
  pname = "atcoder-cli";
  version = "2.2.0";

  src = fetchFromGitHub {
    owner = "Tatamo";
    repo = "atcoder-cli";
    rev = "v${version}";
    hash = "sha256-7pbCTgWt+khKVyMV03HanvuOX2uAC0PL9OLmqly7IWE=";
  };

  # The upstream package-lock.json is used so npm dependencies stay
  # reproducible inside the Nix store.
  npmDepsHash = "sha256-ufG7Fq5D2SOzUp8KYRYUB5tYJYoADuhK+2zDfG0a3ks=";
  npmBuildScript = "build";
  NODE_OPTIONS = "--openssl-legacy-provider";

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/node_modules/${pname}"
    cp -R . "$out/lib/node_modules/${pname}/"

    makeWrapper ${nodejs}/bin/node "$out/bin/acc" \
      --add-flags "$out/lib/node_modules/${pname}/bin/index.js"

    runHook postInstall
  '';

  meta = {
    description = "AtCoder command line tools";
    homepage = "https://github.com/Tatamo/atcoder-cli";
    license = lib.licenses.bsd3;
    mainProgram = "acc";
  };
}
