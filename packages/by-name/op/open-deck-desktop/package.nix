{
  lib,
  fetchurl,
  appimageTools,
  makeWrapper,
}:
let
  pname = "open-deck-desktop";
  version = "1.0.7";
  src = fetchurl {
    url = "https://github.com/kawa-nobu/Open-Deck-Desktop/releases/download/v${version}/Open-Deck-${version}-linux-x86_64.AppImage";
    hash = "sha256-3vedy+0+smWET/lVL7DcG1HL2lHz0AlB3wWFnYOMhjw=";
  };
  contents = appimageTools.extract { inherit pname version src; };
in
appimageTools.wrapType2 {
  inherit pname version src;
  nativeBuildInputs = [ makeWrapper ];
  extraInstallCommands = ''
    # Upstream requires --no-sandbox; no setuid helper is installed by this package.
    wrapProgram $out/bin/${pname} --add-flags --no-sandbox
    install -Dm644 ${contents}/open_deck_desktop.desktop \
      $out/share/applications/open-deck-desktop.desktop
    substituteInPlace $out/share/applications/open-deck-desktop.desktop \
      --replace-fail "Exec=AppRun --no-sandbox" "Exec=${pname}"
    install -Dm644 ${contents}/open_deck_desktop.png \
      $out/share/icons/hicolor/512x512/apps/open_deck_desktop.png
  '';
  meta = {
    description = "Open-Deck desktop application";
    homepage = "https://github.com/kawa-nobu/Open-Deck-Desktop";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = pname;
  };
}
