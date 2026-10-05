{ pkgs, cursor }:
let
  cursorTheme = "Custom-Cursors";
in
pkgs.stdenvNoCC.mkDerivation {
  pname = "custom-cursors";
  version = "1.0";
  src = cursor;
  sourceRoot = ".";
  nativeBuildInputs = [
    pkgs.hyprcursor
    pkgs.unzip
    pkgs.xcur2png
  ];
  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/icons/${cursorTheme}
    cp -r cursors $out/share/icons/${cursorTheme}/
    printf '[Icon Theme]\nName=${cursorTheme}\nComment=Custom cursor theme\n' \
      > $out/share/icons/${cursorTheme}/index.theme

    work="$TMPDIR/custom-cursors-build"
    mkdir -p "$work/custom-cursors"
    cp -r $out/share/icons/${cursorTheme}/. "$work/custom-cursors/"
    chmod -R u+w "$work/custom-cursors"

    # The archive only contains Xcursor assets; generate the matching Hyprcursor theme.
    hyprcursor-util --extract "$work/custom-cursors" >/dev/null
    substituteInPlace "$work/extracted_custom-cursors/manifest.hl" \
      --replace-fail "name = Extracted Theme" "name = ${cursorTheme}" \
      --replace-fail "description = Automatically extracted with hyprcursor-util" "description = Custom cursor theme"
    (cd "$work" && hyprcursor-util --create extracted_custom-cursors >/dev/null)
    cp -r "$work/theme_${cursorTheme}/manifest.hl" "$work/theme_${cursorTheme}/hyprcursors" $out/share/icons/${cursorTheme}/

    runHook postInstall
  '';
}
