# Papirus system-file-manager icon as a 256x256 PNG for the shared file manager desktop entries.
{
  runCommandLocal,
  librsvg,
  papirus-icon-theme,
}:
runCommandLocal "file-manager-icon.png" { nativeBuildInputs = [ librsvg ]; } ''
  rsvg-convert -w 256 -h 256 \
    ${papirus-icon-theme}/share/icons/Papirus/64x64/apps/system-file-manager.svg \
    > $out
''
