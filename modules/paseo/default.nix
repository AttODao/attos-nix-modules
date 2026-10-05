{ config, lib, ... }:
{
  imports = [ ../pi ];

  options.modules.paseo = {
    enable = lib.mkEnableOption "shared Paseo daemon configuration";
    hostname = lib.mkOption {
      type = lib.types.nonEmptyStr;
      description = "Public hostname advertised by Paseo; required when enabled.";
    };
  };

  config = lib.mkIf config.modules.paseo.enable {
    modules.pi.enable = true;
    # ponytail: fixed port supports one active daemon; add per-user ports for concurrent users.
    home-manager.sharedModules = [ ./home.nix ];
  };
}
