{
  autoPatchelfHook,
  curl,
  dbus,
  glib,
  gtk3,
  lib,
  libsecret,
  libsoup_3,
  libuuid,
  libx11,
  nerdFont,
  openssl,
  src,
  stdenv,
  stdenvNoCC,
  webkitgtk_4_1,
  woff2,
}:
let
  manifest = builtins.fromJSON (builtins.readFile "${src}/package.json");
in
stdenvNoCC.mkDerivation {
  pname = "code-server";
  inherit (manifest) version;
  dontUnpack = true;
  nativeBuildInputs = [
    autoPatchelfHook
    woff2
  ];
  buildInputs = map lib.getLib [
    curl
    dbus
    glib
    gtk3
    libsecret
    libsoup_3
    libuuid
    libx11
    openssl
    stdenv.cc.cc
    webkitgtk_4_1
  ];
  CODE_SERVER_SOURCE = src;
  NERD_FONT_FILE = "${nerdFont}/share/fonts/truetype/NerdFonts/JetBrainsMono/JetBrainsMonoNerdFontMono-Regular.ttf";
  NERD_FONT_CSS = ./code-server/nerd-font.css;
  installPhase = builtins.readFile ./code-server/install.sh;
  doInstallCheck = true;
  installCheckPhase = ''
    test -x "$out/bin/code-server"
    test -s "$out/libexec/code-server/src/browser/media/JetBrainsMonoNerdFontMono-Regular.woff2"
    grep -Fq 'nerd-font.css' "$out/libexec/code-server/lib/vscode/out/vs/code/browser/workbench/workbench.html"
  '';
  meta = {
    description = "Standalone code-server with JetBrainsMono Nerd Font in the web workbench";
    homepage = "https://github.com/coder/code-server";
    license = [
      lib.licenses.mit
      lib.licenses.ofl
    ];
    mainProgram = "code-server";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
