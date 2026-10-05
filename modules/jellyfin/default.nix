{ config, lib, ... }:
let
  ps = import ../public-services/lib.nix { inherit lib; };
  s = ps.select config "jellyfin";
  root = ps.require "jellyfin" "dataDir" s.cfg.dataDir;
  mediaDir = ps.require "jellyfin" "mediaDir" s.cfg.mediaDir;
in
{
  imports = [
    ../docker
    ../swarm
    ../ytdl-sub
  ];

  options.modules.public-services = ps.option "jellyfin" (
    ps.common "Jellyfin media server" "http://jellyfin:8096"
    // {
      dataDir = ps.pathOption "Service root containing the existing cache, config, fonts, music and video directories.";
      mediaDir = ps.pathOption "Consumer-selected ytdl-sub media root containing YouTube and Twitch; mounted read-only at /ytdl-sub.";
    }
  );

  config = lib.mkMerge [
    { assertions = s.assertions; }
    (lib.mkIf s.enabled {
      modules.docker.enable = true;
      modules.swarm.enable = true;
      modules.ytdl-sub.enable = true;

      systemd.tmpfiles.rules = map (dir: "d ${builtins.toJSON dir} 0755 root root -") [
        root
        "${root}/cache"
        "${root}/config"
        "${root}/fonts"
        "${root}/music"
        "${root}/video"
      ];
      systemd.services.docker-jellyfin = {
        unitConfig.RequiresMountsFor = [
          root
          mediaDir
        ];
        wants = [ "docker-network-traefik.service" ];
        after = [ "docker-network-traefik.service" ];
      };

      virtualisation.oci-containers.containers.jellyfin = {
        image = lib.mkDefault "jellyfin/jellyfin:12.1@sha256:78d3ea1207d1322471fcac39a614f004f2ccf7e878f95ab2977d752f07e4dd7e";
        user = lib.mkDefault "0:0";
        environment = lib.mapAttrs (_: lib.mkDefault) {
          TZ = "Asia/Tokyo";
          JELLYFIN_PublishedServerUrl = "https://${s.hostname}";
        };
        autoRemoveOnStop = false;
        extraOptions = [
          "--restart=unless-stopped"
          "--add-host=host.docker.internal:host-gateway"
        ];
        volumes = [
          "/etc/localtime:/etc/localtime:ro"
          "${root}/config:/config"
          "${root}/cache:/cache"
          "${root}/music:/music"
          "${root}/video:/video:ro"
          "${mediaDir}:/ytdl-sub:ro"
          "${root}/fonts:/usr/local/share/fonts/custom:ro"
        ];
        networks = [ "traefik" ];
      };
    })
  ];
}
