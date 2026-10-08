{ config, lib, ... }:
let
  ps = import ../public-services/lib.nix { inherit lib; };
  s = ps.select config "jellyfin";
  root = ps.require "jellyfin" "dataDir" s.cfg.dataDir;
  mediaDir = if s.standalone then s.cfg.mediaDir else ps.require "jellyfin" "mediaDir" s.cfg.mediaDir;
in
{
  imports = [
    ../docker
    ../swarm
    ../ytdl-sub
  ];

  options.modules = ps.moduleOptions "jellyfin" (
    ps.common "Jellyfin media server"
    // {
      dataDir = ps.pathOption "Service root containing the existing cache, config, fonts, music and video directories.";
      mediaDir = ps.pathOption "Consumer-selected ytdl-sub media root containing YouTube and Twitch; mounted read-only at /ytdl-sub.";
    }
  );

  config = lib.mkMerge [
    { assertions = s.assertions; }
    (lib.mkIf s.enabled {
      modules.docker.enable = true;
      modules.swarm.enable = lib.mkIf (!s.standalone) true;
      modules.ytdl-sub.enable = lib.mkIf (!s.standalone) true;

      systemd.tmpfiles.rules = map (dir: "d ${builtins.toJSON dir} 0755 root root -") [
        root
        "${root}/cache"
        "${root}/config"
        "${root}/fonts"
        "${root}/music"
        "${root}/video"
      ];
      systemd.services.docker-jellyfin = {
        unitConfig.RequiresMountsFor = [ root ] ++ lib.optional (mediaDir != null) mediaDir;
        wants = [ (ps.networkUnit s) ];
        after = [ (ps.networkUnit s) ];
      };

      virtualisation.oci-containers.containers.jellyfin = {
        image = lib.mkDefault "jellyfin/jellyfin:12.1@sha256:78d3ea1207d1322471fcac39a614f004f2ccf7e878f95ab2977d752f07e4dd7e";
        ports = lib.mkDefault (lib.optional s.standalone "127.0.0.1:8096:8096");
        user = lib.mkDefault "0:0";
        environment = lib.mapAttrs (_: lib.mkDefault) {
          TZ = "Asia/Tokyo";
          JELLYFIN_PublishedServerUrl = ps.url s 8096;
        };
        autoRemoveOnStop = lib.mkDefault false;
        extraOptions = lib.mkDefault [
          "--restart=unless-stopped"
          "--add-host=host.docker.internal:host-gateway"
        ];
        volumes = lib.mkDefault (
          [
            "/etc/localtime:/etc/localtime:ro"
            "${root}/config:/config"
            "${root}/cache:/cache"
            "${root}/music:/music"
            "${root}/video:/video:ro"
          ]
          ++ lib.optional (mediaDir != null) "${mediaDir}:/ytdl-sub:ro"
          ++ [
            "${root}/fonts:/usr/local/share/fonts/custom:ro"
          ]
        );
        networks = lib.mkDefault [ (ps.network s) ];
      };
    })
  ];
}
