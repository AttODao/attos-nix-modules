{
  osConfig,
  config,
  options,
  lib,
  pkgs,
  ...
}:
let
  moduleCfg = osConfig.modules.linux-wallpaperengine;
  cursor =
    if options.home.pointerCursor.highestPrio == (lib.mkOptionDefault { }).priority then
      null
    else
      config.home.pointerCursor;
  cursorTheme = if cursor == null then "Custom-Cursors" else cursor.name;
  cursorSize = if cursor == null then "48" else toString cursor.size;
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

    systemd.user.services.linux-wallpaperengine.Service.Environment = lib.mkDefault [
      "XCURSOR_THEME=${cursorTheme}"
      "XCURSOR_SIZE=${cursorSize}"
      "HYPRCURSOR_THEME=${cursorTheme}"
      "HYPRCURSOR_SIZE=${cursorSize}"
    ];
  };
}
