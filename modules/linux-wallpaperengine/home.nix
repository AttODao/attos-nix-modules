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
  cfg = config.services.linux-wallpaperengine;
  cursor =
    if options.home.pointerCursor.highestPrio == (lib.mkOptionDefault { }).priority then
      null
    else
      config.home.pointerCursor;
  cursorTheme = if cursor == null then "Custom-Cursors" else cursor.name;
  cursorSize = if cursor == null then "48" else toString cursor.size;
  wallpaperCommand = wallpaper: ''
    ${lib.getExe cfg.package} ${
      lib.escapeShellArgs (
        lib.cli.toCommandLineGNU { } (
          lib.filterAttrs (_: value: value != null) {
            assets-dir = cfg.assetsPath;
            inherit (cfg) fps;
            inherit (cfg.audio) silent volume;
            noautomute = !cfg.audio.automute;
            no-audio-processing = !cfg.audio.processing;
          }
        )
        ++ cfg.extraOptions
        ++ [
          "--screen-root"
          wallpaper.monitor
        ]
        ++ lib.optionals (wallpaper.scaling != null) [
          "--scaling"
          wallpaper.scaling
        ]
        ++ lib.optionals (wallpaper.clamp != null) [
          "--clamp"
          wallpaper.clamp
        ]
        ++ wallpaper.extraOptions
        ++ lib.optionals (wallpaper.wallpaper != null) [
          "--bg"
          wallpaper.wallpaper
        ]
        ++ lib.optionals (wallpaper.playlist != null) [
          "--playlist"
          wallpaper.playlist
        ]
      )
    } &
  '';
  wallpaperCommands = pkgs.writeShellScriptBin "linux-wallpaperengine-commands" ''
    set -eu
    ${lib.concatMapStringsSep "\n" wallpaperCommand cfg.wallpapers}
    wait
  '';
in
{
  config = lib.mkIf moduleCfg.enable {
    services.linux-wallpaperengine = {
      enable = true;
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

    systemd.user.services.linux-wallpaperengine.Service = {
      ExecStart = lib.mkForce "${wallpaperCommands}/bin/linux-wallpaperengine-commands";
      Environment = lib.mkDefault [
        "XCURSOR_THEME=${cursorTheme}"
        "XCURSOR_SIZE=${cursorSize}"
        "HYPRCURSOR_THEME=${cursorTheme}"
        "HYPRCURSOR_SIZE=${cursorSize}"
      ];
    };
  };
}
