{ config, lib, ... }:
{
  imports = [ ../fcitx5 ];

  options.modules.discord = {
    enable = lib.mkEnableOption "shared Discord configuration";
    commandLineArgs = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Arguments passed to the host Discord package's commandLineArgs override (for example --ozone-platform=wayland).";
    };
    service.killMode = lib.mkOption {
      type = lib.types.enum [
        "control-group"
        "mixed"
        "process"
        "none"
      ];
      default = "control-group";
      description = "Systemd user service KillMode; mixed allows Electron to shut down children before cleanup.";
    };
  };

  config = lib.mkIf config.modules.discord.enable {
    modules.fcitx5.enable = true;
    home-manager.sharedModules = [ ./home.nix ];
  };
}
