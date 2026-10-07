{ osConfig, lib, ... }:
{
  config = lib.mkIf osConfig.modules.steam.enable {
    xdg.mimeApps = {
      enable = true;
      defaultApplications = {
        "x-scheme-handler/steam" = lib.mkDefault [ "steam.desktop" ];
        "x-scheme-handler/steamlink" = lib.mkDefault [ "steam.desktop" ];
      };
    };
  };
}
