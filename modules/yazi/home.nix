{
  osConfig,
  config,
  lib,
  attopkgs,
  ...
}:
let
  desktopEntry =
    builtins.replaceStrings
      [ "@FOOTCLIENT@" "@YAZI@" ]
      [
        "${config.programs.foot.package}/bin/footclient"
        "${config.programs.yazi.package}/bin/yazi"
      ]
      (builtins.readFile ./yazi.desktop);
in
{
  config = lib.mkIf osConfig.modules.yazi.enable {
    programs.yazi.enable = true;
    xdg = {
      enable = true;
      dataFile."icons/hicolor/256x256/apps/yazi.png".source = attopkgs.file-manager-icon;
      # Replaces the package entry (Terminal=true) so launchers open Yazi in Foot with app-id yazi.
      dataFile."applications/yazi.desktop".text = desktopEntry;
      mimeApps = {
        enable = true;
        defaultApplications = {
          "inode/directory" = lib.mkDefault [ "yazi.desktop" ];
          "x-directory/normal" = lib.mkDefault [ "yazi.desktop" ];
        };
      };
    };
  };
}
