{
  osConfig,
  lib,
  pkgs,
  attopkgs,
  ...
}:
let
  desktopEntry = builtins.replaceStrings [ "@PCMANFM@" ] [ "${pkgs.pcmanfm}/bin/pcmanfm" ] (
    builtins.readFile ./pcmanfm.desktop
  );
in
{
  config = lib.mkIf osConfig.modules.pcmanfm.enable {
    home.packages = [ pkgs.pcmanfm ];
    xdg = {
      enable = true;
      dataFile."icons/hicolor/256x256/apps/pcmanfm.png".source = attopkgs.file-manager-icon;
      dataFile."applications/pcmanfm.desktop".text = desktopEntry;
      # Yazi owns the directory defaults when both are enabled (Hyprland and Steam depend on Yazi).
      mimeApps = lib.mkIf (!osConfig.modules.yazi.enable) {
        enable = true;
        defaultApplications = {
          "inode/directory" = lib.mkDefault [ "pcmanfm.desktop" ];
          "x-directory/normal" = lib.mkDefault [ "pcmanfm.desktop" ];
        };
      };
    };
  };
}
