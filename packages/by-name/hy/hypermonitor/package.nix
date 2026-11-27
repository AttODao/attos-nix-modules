{
  lib,
  stdenvNoCC,
  fetchurl,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "hypermonitor";
  version = "0.2.1";

  src = fetchurl {
    url = "https://git.attodao.cc/AttODao/HyperMonitor/releases/download/server-v${finalAttrs.version}/hypermonitor-server-${finalAttrs.version}-x86_64-linux-musl.tar.gz";
    hash = "sha256-SWiIb2I3zaYixwGvxWCKYnCoFUKhdnX4AsVLg3LLnxw=";
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 bin/hypermonitor "$out/bin/hypermonitor"
    mkdir -p "$out/share/hypermonitor"
    cp -r share/hypermonitor/ui "$out/share/hypermonitor/ui"
    install -Dm644 LICENSE README.md -t "$out/share/doc/hypermonitor"
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    "$out/bin/hypermonitor" --help | grep -q check-config
    test -f "$out/share/hypermonitor/ui/index.html"
    runHook postInstallCheck
  '';

  meta = {
    description = "Dashboard for hosts, public services, forges, HoYoLAB and Hermes (static server and web UI)";
    homepage = "https://git.attodao.cc/AttODao/HyperMonitor";
    license = lib.licenses.gpl3Plus;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "hypermonitor";
  };
})
