{ config, lib, ... }:
{
  imports = [ ../pi ];

  options.modules.paseo = {
    enable = lib.mkEnableOption "shared Paseo daemon configuration";
    hostname = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "localhost";
      description = "Hostname advertised by Paseo; standalone defaults to localhost.";
    };
    environmentFile =
      (import ../public-services/lib.nix { inherit lib; }).pathOption
        "Runtime environment file; null uses each user’s ~/paseo/daemon.env.";
  };

  config = lib.mkIf config.modules.paseo.enable {
    modules.pi.enable = true;
    # ponytail: fixed port supports one active daemon; add per-user ports for concurrent users.
    home-manager.sharedModules = [ ./home.nix ];
  };
}
