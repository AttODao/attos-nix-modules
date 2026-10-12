{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  jq,
}:
buildNpmPackage {
  pname = "pi-mermaid-studio";
  version = "0.2.1";
  src = fetchFromGitHub {
    owner = "irfansofyana";
    repo = "pi-mermaid-studio";
    rev = "42ce06fac0572e7e8672d5ef6c86c1d7a2a23fe1";
    hash = "sha256-52M4BCnQMcFYv+DnweYSDvJchpKPg+5cl1Pp3eydDog=";
  };
  # Upstream's dev-only Pi dependencies lack integrity hashes. Keep the
  # production lock entries unchanged; host-provided peers must not be bundled.
  postPatch = ''
    ${jq}/bin/jq 'del(.devDependencies)' package.json > package.json.tmp
    mv package.json.tmp package.json
    ${jq}/bin/jq 'del(.packages[""].devDependencies) | .packages |= with_entries(select(.value.dev != true))' package-lock.json > package-lock.json.tmp
    mv package-lock.json.tmp package-lock.json
  '';
  npmDepsHash = "sha256-v/ac+X1XfLNQ5L7I/EJU5hufHnF3BKjAOgZsqOtqkMA=";
  npmFlags = [ "--legacy-peer-deps" ];
  npmInstallFlags = [ "--omit=dev" ];
  dontNpmBuild = true;
  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/pi-mermaid-studio
    cp -r package.json extensions src web skills LICENSE node_modules $out/lib/pi-mermaid-studio/
    runHook postInstall
  '';
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    test -f $out/lib/pi-mermaid-studio/node_modules/mermaid/dist/mermaid.esm.min.mjs
    test -f $out/lib/pi-mermaid-studio/skills/mermaid/SKILL.md
    test ! -d $out/lib/pi-mermaid-studio/node_modules/@earendil-works/pi-coding-agent
    test ! -d $out/lib/pi-mermaid-studio/node_modules/@earendil-works/pi-tui
    test ! -d $out/lib/pi-mermaid-studio/node_modules/typebox
    node --input-type=module -e "import { parseHTML } from '$out/lib/pi-mermaid-studio/node_modules/linkedom/esm/index.js'; if (!parseHTML('<html></html>').document) process.exit(1)"
    runHook postInstallCheck
  '';
  meta = {
    description = "Stateful Mermaid workbench for Pi";
    homepage = "https://github.com/irfansofyana/pi-mermaid-studio";
    license = lib.licenses.mit;
  };
}
