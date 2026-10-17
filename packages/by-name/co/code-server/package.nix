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
  nerd-fonts,
  openssl,
  stdenv,
  stdenvNoCC,
  webkitgtk_4_1,
  woff2,
}:
{ src }:
let
  nerdFontFile = "${nerd-fonts.jetbrains-mono}/share/fonts/truetype/NerdFonts/JetBrainsMono/JetBrainsMonoNerdFontMono-Regular.ttf";
  workbenchCss = "{{WORKBENCH_WEB_BASE_URL}}/out/vs/code/browser/workbench/workbench.css";
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
  installPhase = ''
    runHook preInstall

    mkdir -p "$out/bin" "$out/libexec/code-server"
    cp -R ${src}/. "$out/libexec/code-server"
    chmod -R u+w "$out/libexec/code-server"
    ln -s ../libexec/code-server/bin/code-server "$out/bin/code-server"

    media="$out/libexec/code-server/src/browser/media"
    install -m 0644 ${nerdFontFile} "$media/${baseNameOf nerdFontFile}"
    woff2_compress "$media/${baseNameOf nerdFontFile}"
    rm "$media/${baseNameOf nerdFontFile}"
    install -m 0644 ${./nerd-font.css} "$media/nerd-font.css"

    substituteInPlace "$out/libexec/code-server/lib/vscode/out/vs/code/browser/workbench/workbench.html" \
      --replace-fail \
      '<link rel="stylesheet" href="${workbenchCss}">' \
      '<link rel="stylesheet" href="${workbenchCss}">
            <link rel="stylesheet" href="{{BASE}}/_static/src/browser/media/nerd-font.css">'

    runHook postInstall
  '';
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
