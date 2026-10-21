{
  config,
  lib,
  ps,
  ...
}:
{
  imports = [ ../pi ];

  options.modules.paseo = {
    enable = lib.mkEnableOption "shared Paseo daemon configuration";
    hostname = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "localhost";
      description = "Hostname advertised by Paseo; standalone defaults to localhost.";
    };
    environmentFile = ps.pathOption "Runtime environment file; null uses each user’s ~/paseo/daemon.env.";
    relay.enable = lib.mkEnableOption "the Paseo relay, which exposes the daemon beyond the local listener through the relay service";
  };

  config = lib.mkIf config.modules.paseo.enable {
    modules.pi.enable = true;
    # ponytail: fixed port supports one active daemon; add per-user ports for concurrent users.
    home-manager.sharedModules = [ ./home.nix ];
  };
}
