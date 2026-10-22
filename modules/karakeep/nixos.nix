{
  config,
  lib,
  pkgs,
  attopkgs,
  ps,
  ...
}:
let
  s = ps.select config "karakeep";
  cfg = s.cfg;
  dataDir = ps.require "karakeep" "dataDir" cfg.dataDir;
  environmentFile = ps.require "karakeep" "environmentFile" cfg.environmentFile;
  dataUid = toString (ps.require "karakeep" "dataUid" cfg.dataUid);
  dataGid = toString (ps.require "karakeep" "dataGid" cfg.dataGid);
  networkSubnet = "172.20.0.0/16";
  networkGateway = "172.20.0.1";
  chromeAddress = "172.20.0.3";
  baseUrl = ps.url s 3001;

  mounts.unitConfig.RequiresMountsFor = [ dataDir ];

  directory = mode: user: group: {
    d = {
      mode = lib.mkDefault mode;
      user = lib.mkDefault user;
      group = lib.mkDefault group;
    };
  };
in
{
  config = lib.mkIf s.enabled {
    modules.docker.networks.karakeep = {
      subnet = networkSubnet;
      gateway = networkGateway;
    };

    systemd.tmpfiles.settings."10-karakeep" = {
      ${dataDir} = directory "0755" "root" "root";
      "${dataDir}/data" = directory "0755" dataUid dataGid;
      "${dataDir}/meilisearch" = directory "0755" dataUid dataGid;
    };

    systemd.services = {
      docker-karakeep-meilisearch = mounts;
      docker-karakeep-chrome = mounts;
      docker-karakeep = mounts;
    };

    virtualisation.oci-containers.containers = {
      karakeep-meilisearch = {
        image = lib.mkDefault "getmeili/meilisearch:v1.55.0@sha256:ff546679970126f8822e15d1b6a06bfbff1f2ce2e43f810cfb5258012f92de5c";
        environmentFiles = lib.mkDefault [ environmentFile ];
        environment = {
          MEILI_NO_ANALYTICS = lib.mkDefault "true";
          # Meilisearch only opens databases from older versions with this opt-in.
          MEILI_UPGRADE_DB = lib.mkDefault "true";
        };
        autoRemoveOnStop = lib.mkDefault false;
        extraOptions = lib.mkDefault [
          "--restart=unless-stopped"
          "--network-alias=meilisearch"
        ];
        volumes = lib.mkDefault [ "${dataDir}/meilisearch:/meili_data" ];
        networks = lib.mkDefault [ "karakeep" ];
      };

      karakeep-chrome = {
        # Official image labels: Chrome 154.0.8037.57; no version tag exists.
        # Review browser updates and replace this registry index digest explicitly.
        image = lib.mkDefault "ghcr.io/karakeep-app/karakeep-chrome:release@sha256:4ad61127638dd27bfe685222787c5780dd1d083d23a7658c39af657775814c44";
        autoRemoveOnStop = lib.mkDefault false;
        extraOptions = lib.mkDefault [
          "--restart=unless-stopped"
          "--init"
          "--network-alias=chrome"
          "--ip=${chromeAddress}"
        ];
        cmd = lib.mkDefault [
          "--disable-gpu"
          "--disable-dev-shm-usage"
          "--hide-scrollbars"
          "--disable-blink-features=AutomationControlled"
          "--window-size=1440,900"
        ];
        # The Chrome image only ships Latin fonts; retain crawler glyphs.
        volumes = lib.mkDefault [
          "${pkgs.noto-fonts-cjk-sans}/share/fonts/opentype/noto-cjk:/usr/local/share/fonts/noto-cjk:ro"
        ];
        networks = lib.mkDefault [ "karakeep" ];
      };

      karakeep = {
        image = lib.mkDefault "ghcr.io/karakeep-app/karakeep:0.34.0@sha256:151cdd6b5f2e21635645983e126f411675bfa35becb02c028c1a727f45f899c6";
        ports = lib.mkDefault (ps.publish s 3001 3000);
        environmentFiles = lib.mkDefault [ environmentFile ];
        environment = lib.mapAttrs (_: lib.mkDefault) (
          {
            DATA_DIR = "/data";
            NEXTAUTH_URL = baseUrl;
            MEILI_ADDR = "http://meilisearch:7700";
            # DevTools rejects a DNS name in the Host header.
            BROWSER_WEB_URL = "http://${chromeAddress}:9222";
            LOG_LEVEL = "notice";
            DB_WAL_MODE = "true";
            RATE_LIMITING_ENABLED = "true";
            CRAWLER_FULL_PAGE_ARCHIVE = "true";
            CRAWLER_MONOLITH_TIMEOUT_SEC = "300";
            CRAWLER_JOB_TIMEOUT_SEC = "900";
            MONOLITH_FRAGMENT_NAVIGATION_PREFIX = "${baseUrl}/api/assets/";
          }
          // cfg.environment
        );
        autoRemoveOnStop = lib.mkDefault false;
        extraOptions = lib.mkDefault [
          "--restart=unless-stopped"
          "--network-alias=karakeep"
        ];
        volumes = lib.mkDefault [
          "/etc/localtime:/etc/localtime:ro"
          "${dataDir}/data:/data"
          "${attopkgs.karakeep-monolith}/bin/monolith:/usr/local/bin/monolith:ro"
        ];
        dependsOn = lib.mkDefault [
          "karakeep-meilisearch"
          "karakeep-chrome"
        ];
        networks = lib.mkDefault [
          "karakeep"
        ];
      };
    };
  };
}
