{
  lib,
  fetchurl,
  appimageTools,
  flavor ? "amd-rx7900",
  # Port the app's LAN sharing listener prefers (upstream default: its host port + 1).
  sharePort ? null,
}:
let
  pname = "strata-desktop";
  version = "0.2.2";
  flavors = {
    amd-rx7900 = {
      file = "Strata-${version}-linux-amd-rx7900.AppImage";
      hash = "sha256-p3o8E7sXR6MFKE6xz0gXHQUVys4hephrNSFNsxkqgDI=";
    };
  };
  release = flavors.${flavor} or (throw "Unsupported Strata desktop flavor: ${flavor}");
  src = fetchurl {
    url = "https://github.com/Niko1221/Strata/releases/download/v${version}/${release.file}";
    inherit (release) hash;
  };
  contents = appimageTools.extract { inherit pname version src; };
in
appimageTools.wrapType2 {
  inherit pname version src;
  profile = lib.optionalString (sharePort != null) ''
    export STRATA_SHARE_PORT=${toString sharePort}
  '';
  # The image bundles WebKitGTK 4.1, GTK, Node, Python and its HIP engine.
  # appimageTools supplies the excluded system libraries (libdrm, Wayland,
  # libgbm, fontconfig, etc.); do not mix a second WebKitGTK into that bundle.
  extraInstallCommands = ''
    install -Dm644 ${contents}/Strata.desktop \
      $out/share/applications/strata-desktop.desktop
    substituteInPlace $out/share/applications/strata-desktop.desktop \
      --replace-fail "Exec=strata-desktop" "Exec=$out/bin/${pname}"
    install -Dm644 ${contents}/strata-desktop.png \
      $out/share/icons/hicolor/512x512/apps/strata-desktop.png
  '';
  meta = {
    description = "Strata local AI desktop application (AMD RX 7000)";
    homepage = "https://github.com/Niko1221/Strata";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = pname;
  };
}
