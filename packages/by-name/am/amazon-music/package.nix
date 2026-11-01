{
  lib,
  stdenvNoCC,
  fetchurl,
  writeShellApplication,
  writeText,
  makeDesktopItem,
  copyDesktopItems,
  icoutils,
  wineWow64Packages,
}:
let
  pname = "amazon-music";
  # Final standalone Windows release; Amazon no longer publishes newer installers.
  version = "9.5.2.2478";
  installer = fetchurl {
    url = "https://d2j9xt6n9dg5d3.cloudfront.net/win/24780926_1c962c14fdc55b2e347aeb3c3ffc5ee6/AmazonMusicInstaller.exe";
    hash = "sha256-rt8fMvN/WgsL55rimuvxLz3Y6ZGPn9rr7hB/3zlzQ6c=";
  };
  wine = wineWow64Packages.stagingFull;
  # InputStyle=root lets fcitx5 (XIM) input reach the CEF window; ShowSystray=0 hides
  # Wine's fallback tray window, which Wayland compositors show as a stray small window.
  registry = writeText "amazon-music.reg" ''
    Windows Registry Editor Version 5.00

    [HKEY_CURRENT_USER\Software\Wine\X11 Driver]
    "InputStyle"="root"

    [HKEY_CURRENT_USER\Software\Wine\Explorer]
    "ShowSystray"=dword:00000000
  '';
  launcher = writeShellApplication {
    name = pname;
    runtimeInputs = [ wine ];
    text = ''
      data="''${XDG_DATA_HOME:-$HOME/.local/share}/amazon-music"
      export WINEPREFIX="$data/prefix"
      export WINEDEBUG=-all
      # No menu entries or file associations from winemenubuilder; no Mono/Gecko install prompts.
      export WINEDLLOVERRIDES="winemenubuilder.exe=d;mscoree,mshtml="
      # Use the X11 driver through Xwayland; the Wayland driver draws Wine's own title bar.
      export DISPLAY="''${DISPLAY:-:0}"

      user="''${USER:-$(id -un)}"
      exe="$WINEPREFIX/drive_c/users/$user/AppData/Local/Amazon Music/Amazon Music.exe"
      mkdir -p "$data"

      # Re-apply the registry only when it changes; the first run also creates the prefix.
      # Restart the prefix afterwards: explorer.exe started by prefix creation has already
      # read ShowSystray and would keep its tray window.
      if [ "$(cat "$data/registry-applied" 2>/dev/null || true)" != "${registry}" ]; then
        wine regedit /S ${registry}
        wineserver -k || true
        printf '%s\n' "${registry}" >"$data/registry-applied"
      fi

      if [ ! -e "$exe" ]; then
        # The installer exits 1 after a harmless ie4uinit failure, so check the result instead.
        wine ${installer} --unattendedmodeui none || true
        if [ ! -e "$exe" ]; then
          echo "amazon-music: installation failed" >&2
          exit 1
        fi
      fi

      # CEF's GPU process fails to initialize under Wine and leaves no window without these.
      exec wine "$exe" --disable-gpu --disable-gpu-compositing "$@"
    '';
  };
in
stdenvNoCC.mkDerivation {
  inherit pname version;
  dontUnpack = true;
  nativeBuildInputs = [
    icoutils
    copyDesktopItems
  ];
  desktopItems = [
    (makeDesktopItem {
      name = pname;
      desktopName = "Amazon Music";
      comment = "Amazon Music for Windows running in Wine";
      exec = pname;
      icon = pname;
      startupWMClass = "amazon music.exe";
      categories = [
        "AudioVideo"
        "Audio"
        "Player"
      ];
    })
  ];
  installPhase = ''
    runHook preInstall
    install -Dm755 ${lib.getExe launcher} $out/bin/${pname}
    wrestool -x -t14 ${installer} -o icon.ico
    # Only the 256px entry is a PNG; icotool rejects the smaller malformed BMP entries.
    icotool -x -w 256 -h 256 -o icon.png icon.ico
    install -Dm644 icon.png $out/share/icons/hicolor/256x256/apps/${pname}.png
    runHook postInstall
  '';
  meta = {
    description = "Amazon Music desktop app for Windows, installed into a per-user Wine prefix";
    homepage = "https://music.amazon.com/";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = pname;
  };
}
