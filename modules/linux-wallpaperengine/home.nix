{
  osConfig,
  config,
  lib,
  pkgs,
  ...
}:
let
  moduleCfg = osConfig.modules.linux-wallpaperengine;
in
{
  config = lib.mkIf moduleCfg.enable {
    services.linux-wallpaperengine = {
      # Upstream starts without --screen-root when the list is empty.
      enable = lib.mkDefault (moduleCfg.wallpapers != [ ]);
      package = lib.mkDefault pkgs.linux-wallpaperengine;
      assetsPath = lib.mkDefault "${config.home.homeDirectory}/.local/share/Steam/steamapps/common/wallpaper_engine/assets";
      audio = {
        silent = lib.mkDefault true;
        processing = lib.mkDefault false;
      };
      wallpapers = lib.mkDefault (
        map (wallpaper: wallpaper // { scaling = "fill"; }) moduleCfg.wallpapers
      );
    };
  };
}
