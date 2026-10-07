{
  osConfig,
  config,
  lib,
  pkgs,
  ...
}:
let
  desktopEntry = builtins.replaceStrings [ "@PCMANFM@" ] [ "${pkgs.pcmanfm}/bin/pcmanfm" ] (
    builtins.readFile ./pcmanfm.desktop
  );
  icon = pkgs.runCommandLocal "pcmanfm-icon.png" { nativeBuildInputs = [ pkgs.librsvg ]; } ''
    rsvg-convert -w 256 -h 256 \
      ${pkgs.papirus-icon-theme}/share/icons/Papirus/64x64/apps/system-file-manager.svg \
      > $out
  '';
in
{
  config = lib.mkIf osConfig.modules.pcmanfm.enable {
    home.packages = [ pkgs.pcmanfm ];
    xdg = {
      enable = true;
      dataFile."icons/hicolor/256x256/apps/pcmanfm.png".source = icon;
      dataFile."applications/pcmanfm.desktop".text = desktopEntry;
      mimeApps = {
        enable = true;
        defaultApplications = {
          "inode/directory" = lib.mkDefault [ "pcmanfm.desktop" ];
          "x-directory/normal" = lib.mkDefault [ "pcmanfm.desktop" ];
        };
      };
    };
  };
}
