{
  config,
  lib,
  pkgs,
  attopkgs,
  ...
}:
let
  ps = import ../public-services/lib.nix { inherit lib; };
  s = ps.select config "karakeep";
  cfg = s.cfg;
  dataDir = ps.require "karakeep" "dataDir" cfg.dataDir;
  environmentFile = ps.require "karakeep" "environmentFile" cfg.environmentFile;
  dataUid = toString (ps.require "karakeep" "dataUid" cfg.dataUid);
  dataGid = toString (ps.require "karakeep" "dataGid" cfg.dataGid);
  networkSubnet = "172.20.0.0/24";
  networkGateway = "172.20.0.1";
  chromeAddress = "172.20.0.3";
  baseUrl = "https://${s.hostname}";

  ensureNetwork = lib.replaceStrings [ "@docker@" "@subnet@" "@gateway@" ] (map lib.escapeShellArg [
    "${pkgs.docker}/bin/docker"
    networkSubnet
    networkGateway
  ]) (builtins.readFile ./ensure-network.sh);

  networkDep = {
    unitConfig.RequiresMountsFor = [ dataDir ];
    requires = [ "docker-network-karakeep.service" ];
    after = [ "docker-network-karakeep.service" ];
    # Recheck after prune even when the persistent oneshot remains active.
    preStart = lib.mkBefore ensureNetwork;
  };

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
    systemd.tmpfiles.settings."10-karakeep" = {
      ${dataDir} = directory "0755" "root" "root";
      "${dataDir}/data" = directory "0755" dataUid dataGid;
      "${dataDir}/meilisearch" = directory "0755" dataUid dataGid;
    };

    systemd.services = {
      docker-network-karakeep = {
        description = lib.mkDefault "Create docker network karakeep";
        wantedBy = [ "multi-user.target" ];
        after = [
          "docker.service"
          "docker.socket"
        ];
        requires = [ "docker.service" ];
        serviceConfig = {
          Type = lib.mkDefault "oneshot";
          RemainAfterExit = lib.mkDefault true;
        };
        script = lib.mkDefault ensureNetwork;
      };
      docker-karakeep-meilisearch = networkDep;
      docker-karakeep-chrome = networkDep;
      docker-karakeep = lib.mkMerge [
        networkDep
        {
          wants = [ "docker-network-traefik.service" ];
          after = [ "docker-network-traefik.service" ];
        }
      ];
    };

    virtualisation.oci-containers.containers = {
      karakeep-meilisearch = {
        image = lib.mkDefault "getmeili/meilisearch:v1.54.3@sha256:e68913ab7d6f5b159529e472cfd362ce3c741fafd3c127961b2142abbe41b3c9";
        environmentFiles = lib.mkDefault [ environmentFile ];
        environment.MEILI_NO_ANALYTICS = lib.mkDefault "true";
        autoRemoveOnStop = lib.mkDefault false;
        extraOptions = lib.mkDefault [
          "--restart=unless-stopped"
          "--network-alias=meilisearch"
        ];
        volumes = lib.mkDefault [ "${dataDir}/meilisearch:/meili_data" ];
        networks = lib.mkDefault [ "karakeep" ];
      };

      karakeep-chrome = {
        image = lib.mkDefault "ghcr.io/karakeep-app/karakeep-chrome:release";
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
        image = lib.mkDefault "ghcr.io/karakeep-app/karakeep:0.33.2";
        environmentFiles = lib.mkDefault [ environmentFile ];
        environment = lib.mapAttrs (_: lib.mkDefault) {
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
        };
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
          "traefik"
        ];
      };
    };
  };
}
