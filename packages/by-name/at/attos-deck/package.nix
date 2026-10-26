{
  lib,
  stdenvNoCC,
  fetchurl,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "attos-deck";
  version = "0.1.0";

  src = fetchurl {
    url = "https://git.attodao.cc/AttODao/attos-deck/releases/download/v${finalAttrs.version}/attos-deck-${finalAttrs.version}-x86_64-linux-musl.tar.gz";
    hash = "sha256-WbP7HVJRak7uegG5DuGpFCDJQpzSx+XCR7+2skcS550=";
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 bin/attos-deck "$out/bin/attos-deck"
    install -Dm755 bin/attos-deck-agent "$out/bin/attos-deck-agent"
    install -Dm644 LICENSE README.md -t "$out/share/doc/attos-deck"
    install -Dm644 contrib/* -t "$out/share/attos-deck"
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    "$out/bin/attos-deck" --help
    # The agent prints usage and exits non-zero without a subcommand; only check that it runs.
    ("$out/bin/attos-deck-agent" 2>&1 || true) | grep -q serve
    runHook postInstallCheck
  '';

  meta = {
    description = "Stream Deck MK.2 status controller and its systemctl agent";
    homepage = "https://git.attodao.cc/AttODao/attos-deck";
    license = lib.licenses.gpl3Plus;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "attos-deck";
  };
})
