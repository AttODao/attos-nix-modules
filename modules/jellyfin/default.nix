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
      };

      virtualisation.oci-containers.containers.jellyfin = {
        image = lib.mkDefault "jellyfin/jellyfin:12.2@sha256:357724bf0ae27a672c7cbaa899db2d9abeb13dbd8657ccce750258a4c059d037";
        ports = lib.mkDefault (ps.publish s 8096 8096);
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
      };
    })
  ];
}
