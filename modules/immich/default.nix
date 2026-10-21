{
  config,
  lib,
  ps,
  ...
}:
let
  s = ps.select config "immich";
  root = ps.require "immich" "dataDir" s.cfg.dataDir;
  listen = ps.listen s 2283;
in
{
  options.modules = ps.moduleOptions "immich" (
    ps.common "shared Immich photo service"
    // {
      dataDir = ps.pathOption "Persistent Immich root whose library directory holds the media (visible to Immich at /data).";
    }
  );

  config = lib.mkMerge [
    { assertions = s.assertions; }
    (lib.mkIf s.enabled {
      services.immich = {
        enable = true;
        host = listen.address;
        port = listen.port;
        # The database stores absolute /data paths from the official image; keep them valid.
        mediaLocation = "/data";
      };
      systemd.tmpfiles.settings."10-immich" = {
        ${root}.d = {
          mode = "0755";
          user = "root";
          group = "root";
        };
        "${root}/library".d = {
          mode = "0700";
          user = "immich";
          group = "immich";
        };
        # Mount point for the per-service bind below.
        "/data".d = {
          mode = "0700";
          user = "immich";
          group = "immich";
        };
      };
      systemd.services.immich-server = {
        unitConfig.RequiresMountsFor = [ root ];
        inherit (ps.afterNetworkOnline) wants after;
        serviceConfig.BindPaths = [ "${root}/library:/data" ];
      };
      networking.firewall = ps.backendFirewall config s [ ];
    })
  ];
}
