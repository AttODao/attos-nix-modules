{
  osConfig,
  config,
  lib,
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
      assetsPath = lib.mkDefault "${config.home.homeDirectory}/.local/share/Steam/steamapps/common/wallpaper_engine/assets";
      audio = {
        silent = lib.mkDefault true;
        processing = lib.mkDefault false;
      };
      wallpapers = lib.mkDefault (
        map (wallpaper: wallpaper // { scaling = "fill"; }) moduleCfg.wallpapers
      );
    };
    # The upstream unit restarts on failure; Requisite keeps a restart after logout from
    # starting it without a display.
    systemd.user.services.linux-wallpaperengine =
      lib.mkIf config.services.linux-wallpaperengine.enable
        {
          Unit.Requisite = [ "graphical-session.target" ];
        };
  };
}
