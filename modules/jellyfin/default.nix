{
  config,
  lib,
  ps,
  ...
}:
let
  s = ps.select config "jellyfin";
  root = ps.require "jellyfin" "dataDir" s.cfg.dataDir;
  mediaDir = if s.standalone then s.cfg.mediaDir else ps.require "jellyfin" "mediaDir" s.cfg.mediaDir;
in
{
  imports = [ ../ytdl-sub ];

  options.modules = ps.moduleOptions "jellyfin" (
    ps.common "Jellyfin media server"
    // {
      dataDir = ps.pathOption "Service root in the official image layout: cache, config, fonts, music and video directories (created when missing); required when deployed locally.";
      mediaDir = ps.pathOption "ytdl-sub media root (normally modules.ytdl-sub.dataDir), visible read-only at /ytdl-sub; required for a public deployment, optional standalone.";
    }
  );

  config = lib.mkMerge [
    { assertions = s.assertions; }
    (lib.mkIf (s.enabled && !s.standalone) {
      assertions = [
        {
          assertion = (ps.backendEndpoint s).port == "8096";
          message = "jellyfin: backendUrl must use port 8096, where the existing server configuration listens.";
        }
      ];
    })
    (lib.mkIf s.enabled {
      modules.ytdl-sub.enable = lib.mkIf (!s.standalone) true;

      systemd.tmpfiles.rules = map (dir: "d ${builtins.toJSON dir} 0750 jellyfin jellyfin -") [
        root
        "${root}/cache"
        "${root}/config"
        "${root}/fonts"
        "${root}/music"
        "${root}/video"
      ];

      # Keep the official image layout so existing library and metadata paths stay valid.
      # configDir and logDir follow dataDir upstream (config/config and config/log).
      services.jellyfin = {
        enable = true;
        dataDir = "${root}/config";
        cacheDir = "${root}/cache";
      };
      systemd.services.jellyfin = {
        unitConfig.RequiresMountsFor = [ root ] ++ lib.optional (mediaDir != null) mediaDir;
        serviceConfig = {
          BindReadOnlyPaths = [
            "${root}/video:/video"
            "${root}/fonts:/usr/local/share/fonts/custom"
          ]
          ++ lib.optional (mediaDir != null) "${mediaDir}:/ytdl-sub";
          # The database stores library roots and image paths under the container's /config and /cache.
          BindPaths = [
            "${root}/music:/music"
            "${root}/config:/config"
            "${root}/cache:/cache"
          ];
        };
      };
      networking.firewall = ps.backendFirewall config s [ ];
    })
  ];
}
