{ config, lib, ... }:
{
  options.modules.noctalia = {
    enable = lib.mkEnableOption "shared Noctalia configuration";
    dock.pinned = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
      ];
      description = "Desktop entry IDs pinned to the dock (replaces the default list).";
    };
    screenRecorder.enable = lib.mkEnableOption "Noctalia screen recorder";
  };

  config = lib.mkIf config.modules.noctalia.enable {
    home-manager.sharedModules = [ ./home.nix ];
  };
}
