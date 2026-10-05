{ config, lib, ... }:
{
  options.modules.linux-wallpaperengine = {
    enable = lib.mkEnableOption "linux-wallpaperengine";
    wallpapers = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            monitor = lib.mkOption {
              type = lib.types.str;
              description = "Monitor on which to display the wallpaper.";
            };
            wallpaper = lib.mkOption {
              type = lib.types.str;
              description = "Steam Workshop ID or path to the wallpaper directory.";
            };
            scaling = lib.mkOption {
              type = lib.types.enum [
                "stretch"
                "fit"
                "fill"
                "default"
              ];
              default = "fill";
              description = "Wallpaper scaling mode.";
            };
          };
        }
      );
      default = [ ];
      description = "Wallpapers to display on each monitor.";
    };
  };

  config = lib.mkIf config.modules.linux-wallpaperengine.enable {
    home-manager.sharedModules = [ ./home.nix ];
  };
}
