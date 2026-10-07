{
  lib,
  imagemagick,
  runCommand,
  image,
}:

runCommand "centered-plymouth-theme" { } ''
  themeDir="$out/share/plymouth/themes/centered-logo"
  mkdir -p "$themeDir"

  substitute ${../modules/limine/centered-logo.plymouth} "$themeDir/centered-logo.plymouth" \
    --replace-fail "@THEME_DIR@" "$themeDir"
  cp ${../modules/limine/centered-logo.script} "$themeDir/centered-logo.script"
  ${imagemagick}/bin/magick \
    ${lib.escapeShellArg image} \
    -resize '960x360>' \
    "$themeDir/logo.png"
''
