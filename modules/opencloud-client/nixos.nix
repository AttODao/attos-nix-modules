{ config, lib, ... }:
let
  cfg = config.modules.opencloud-client;
in
{
  config = lib.mkIf cfg.enable {
    # OpenCloud reads this system file before its per-user configuration exists.
    environment.etc."OpenCloud/OpenCloud.conf".text = ''
      [Wizard]
      ServerUrl=${toString cfg.serverUrl}
    '';
  };
}
