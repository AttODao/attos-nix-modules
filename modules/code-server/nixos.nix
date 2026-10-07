{ config, lib, ... }:
let
  ps = import ../public-services/lib.nix { inherit lib; };
  selected = ps.select config "code-server";
  cfg = selected.cfg;
  native = config.services.code-server;
  environmentFile =
    if native.auth == "password" then
      ps.require "code-server" "environmentFile for password authentication" cfg.environmentFile
    else
      cfg.environmentFile;
in
{
  config = lib.mkIf selected.enabled {
    services.code-server = {
      enable = true;
      host = lib.mkDefault "0.0.0.0";
      port = lib.mkDefault 4444;
      auth = lib.mkDefault "password";
      disableTelemetry = lib.mkDefault true;
      disableUpdateCheck = lib.mkDefault true;
      extraEnvironment.HOME = lib.mkDefault config.users.users.${native.user}.home;
    };

    # Existing user data and credentials remain writable and unmanaged.
    systemd.services.code-server = {
      serviceConfig.UMask = lib.mkDefault "0077";
      serviceConfig.EnvironmentFile = lib.mkIf (environmentFile != null) environmentFile;
      unitConfig.ConditionPathExists = lib.mkIf (environmentFile != null) environmentFile;
      unitConfig.RequiresMountsFor =
        lib.optional (environmentFile != null) environmentFile
        ++ lib.optional (native.userDataDir != null) native.userDataDir
        ++ lib.optional (native.extensionsDir != null) native.extensionsDir;
    };
  };
}
