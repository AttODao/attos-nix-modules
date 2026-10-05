{
  osConfig,
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = osConfig.modules.linux-wallpaperengine;
  assetsPath = "${config.home.homeDirectory}/.local/share/Steam/steamapps/common/wallpaper_engine/assets";
  wallpaperCommands = pkgs.writeShellScriptBin "linux-wallpaperengine-commands" ''
    set -eu
    ${lib.concatMapStringsSep "\n" (wallpaper: ''
      ${lib.getExe pkgs.linux-wallpaperengine} \
        --assets-dir ${lib.escapeShellArg assetsPath} \
        --screen-root ${lib.escapeShellArg wallpaper.monitor} \
        --scaling ${lib.escapeShellArg wallpaper.scaling} \
        --silent --no-audio-processing \
        --bg ${lib.escapeShellArg wallpaper.wallpaper} &
    '') cfg.wallpapers}
    wait
  '';
in
{
  config = lib.mkIf cfg.enable {
    services.linux-wallpaperengine = {
      enable = true;
      package = pkgs.linux-wallpaperengine;
      inherit assetsPath;
      audio = {
        silent = true;
        processing = false;
      };
      wallpapers = cfg.wallpapers;
    };

    systemd.user.services.linux-wallpaperengine.Service = {
      ExecStart = lib.mkForce "${wallpaperCommands}/bin/linux-wallpaperengine-commands";
      Environment = [
        "XCURSOR_THEME=Custom-Cursors"
        "XCURSOR_SIZE=48"
        "HYPRCURSOR_THEME=Custom-Cursors"
        "HYPRCURSOR_SIZE=48"
      ];
    };
  };
}
