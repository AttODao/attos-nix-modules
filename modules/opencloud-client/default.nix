{ config, lib, ... }:
{
  imports = [ ./nixos.nix ];

  options.modules.opencloud-client = {
    enable = lib.mkEnableOption "shared OpenCloud desktop client";
    serverUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.nonEmptyStr;
      default = null;
      example = "https://cloud.example.org";
      description = "Server URL preset in the client's account wizard; required when enabled.";
    };
  };

  config = lib.mkIf config.modules.opencloud-client.enable {
    assertions = [
      {
        assertion = config.modules.opencloud-client.serverUrl != null;
        message = "modules.opencloud-client.serverUrl is required when enabled.";
      }
    ];
    home-manager.sharedModules = [ ./home.nix ];
  };
}
