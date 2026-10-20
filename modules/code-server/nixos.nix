{
  config,
  lib,
  attopkgs,
  ...
}:
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
  # Standalone stays on loopback; a public owner listens on its backendUrl like the other native services.
  listen =
    if selected.standalone then
      {
        address = "127.0.0.1";
        port = "4444";
      }
    else
      ps.backendEndpoint selected;
in
{
  config = lib.mkIf selected.enabled {
    services.code-server = {
      enable = true;
      package = lib.mkIf (cfg.packageSource != null) (
        lib.mkDefault (attopkgs.code-server { src = cfg.packageSource; })
      );
      user = lib.mkDefault cfg.user;
      group = lib.mkDefault cfg.group;
      host = lib.mkDefault (lib.removeSuffix "]" (lib.removePrefix "[" listen.address));
      port = lib.mkDefault (lib.toInt listen.port);
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
      # A public owner binds the backendUrl address, which must exist first.
      wants = lib.mkIf (!selected.standalone) [ "network-online.target" ];
      after = lib.mkIf (!selected.standalone) [ "network-online.target" ];
    };
    networking.firewall = ps.backendFirewall config selected [ ];
  };
}
