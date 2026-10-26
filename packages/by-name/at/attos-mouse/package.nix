{
  lib,
  stdenvNoCC,
  fetchurl,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "attos-mouse";
  version = "0.1.0";

  src = fetchurl {
    url = "https://git.attodao.cc/AttODao/attos-mouse/releases/download/v${finalAttrs.version}/attos-mouse-${finalAttrs.version}-x86_64-linux-musl.tar.gz";
    hash = "sha256-Ew9BGPqjlOjCvrrpa3bIdxsgm61rdkvqfzylVBRaAt0=";
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 bin/attos-mouse "$out/bin/attos-mouse"
    install -Dm644 LICENSE README.md -t "$out/share/doc/attos-mouse"
    install -Dm644 contrib/attos-mouse.service "$out/share/attos-mouse/attos-mouse.service"
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    "$out/bin/attos-mouse" --help
    runHook postInstallCheck
  '';

  meta = {
    description = "Logitech MX Master 4 driver and Wayland ring menu";
    homepage = "https://git.attodao.cc/AttODao/attos-mouse";
    license = lib.licenses.gpl3Plus;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "attos-mouse";
  };
})
