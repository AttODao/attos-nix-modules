{ config, lib, ... }:
{
  options.modules.strata-desktop = {
    enable = lib.mkEnableOption "shared Strata desktop configuration";
    sharePort = lib.mkOption {
      type = lib.types.nullOr lib.types.port;
      default = null;
      example = 8080;
      description = "Port the app's LAN sharing listener (0.0.0.0, toggled in the app) prefers; null keeps upstream's choice. Opening the firewall is left to the consumer.";
    };
  };

  config = lib.mkIf config.modules.strata-desktop.enable {
    home-manager.sharedModules = [ ./home.nix ];
  };
}
