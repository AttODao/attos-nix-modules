{ config, lib, ... }:
let
  ps = import ../public-services/lib.nix { inherit lib; };
  s = ps.select config "mineos";
  root = ps.require "mineos" "dataDir" s.cfg.dataDir;
  environmentFile = ps.require "mineos" "environmentFile" s.cfg.environmentFile;
  uid = toString (ps.require "mineos" "uid" s.cfg.uid);
  gid = toString (ps.require "mineos" "gid" s.cfg.gid);
  origin = "https://${s.hostname}";
in
{
  imports = [
    ../docker
    ../swarm
  ];

  options.modules.public-services = ps.option "mineos" (
    ps.common "MineOS Minecraft management" "http://web:3000"
    // {
      dataDir = ps.pathOption "Service root containing data, archives, backups, imports, profiles and servers.";
      environmentFile = ps.pathOption "Runtime MineOS environment file containing credentials.";
      gameHost = lib.mkOption {
        type = lib.types.nonEmptyStr;
        default = "api";
        description = "Minecraft upstream host reachable by Traefik (without a port).";
      };
      tcpPorts = lib.mkOption {
        type = lib.types.listOf lib.types.port;
        default = lib.range 25500 25600;
        description = "Minecraft TCP ports forwarded by Traefik; override allocation separately through standard MineOS environment settings if needed.";
      };
      udpPorts = lib.mkOption {
        type = lib.types.listOf lib.types.port;
        default = lib.range 19132 19137;
        description = "Bedrock UDP ports forwarded by Traefik. Private services must disable these and arrange VPN-only ingress in the consumer.";
      };
      uid = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.unsigned;
        default = null;
        description = "Consumer-selected UID for Minecraft server files managed by MineOS.";
      };
      gid = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.unsigned;
        default = null;
        description = "Consumer-selected GID for Minecraft server files managed by MineOS.";
      };
    }
  );

  config = lib.mkMerge [
    { assertions = s.assertions; }
    (lib.mkIf s.enabled {
      modules.docker.enable = true;
      modules.swarm.enable = true;

      systemd.services.docker-mineos-api = {
        unitConfig.RequiresMountsFor = [
          root
          environmentFile
        ];
        wants = [ "docker-network-traefik.service" ];
        after = [ "docker-network-traefik.service" ];
        serviceConfig.TimeoutStopSec = lib.mkDefault "10min";
      };
      systemd.services.docker-mineos-web = {
        unitConfig.RequiresMountsFor = [
          root
          environmentFile
        ];
        wants = [ "docker-network-traefik.service" ];
        after = [
          "docker-network-traefik.service"
          "docker-mineos-api.service"
        ];
      };
      systemd.tmpfiles.rules = map (dir: "d ${builtins.toJSON dir} 0755 root root -") [
        root
        "${root}/data"
        "${root}/archives"
        "${root}/backups"
        "${root}/imports"
        "${root}/profiles"
        "${root}/servers"
      ];

      virtualisation.oci-containers.containers = {
        mineos-api = {
          image = lib.mkDefault "ghcr.io/freeman412/mineos-api:latest";
          pull = lib.mkDefault "always";
          environmentFiles = [ environmentFile ];
          environment = lib.mapAttrs (_: lib.mkDefault) {
            ASPNETCORE_ENVIRONMENT = "Production";
            ASPNETCORE_URLS = "http://+:5078";
            ConnectionStrings__DefaultConnection = "Data Source=/app/data/mineos.db";
            API_PORT = "5078";
            Host__BaseDirectory = "/var/games/minecraft";
            Host__ServersPathSegment = "servers";
            Host__ProfilesPathSegment = "profiles";
            Host__BackupsPathSegment = "backups";
            Host__ArchivesPathSegment = "archives";
            Host__ImportsPathSegment = "imports";
            Host__OwnerUid = uid;
            Host__OwnerGid = gid;
            WEB_PORT = "3000";
            MC_PORT_RANGE = "25500-25600";
            BEDROCK_PORT_RANGE = "19132-19137";
            Cors__AllowedOrigins__0 = origin;
            Logging__LogLevel__Default = "Information";
            "Logging__LogLevel__Microsoft.AspNetCore" = "Warning";
            MINEOS_SHUTDOWN_TIMEOUT = "600";
          };
          autoRemoveOnStop = false;
          extraOptions = [
            "--restart=unless-stopped"
            "--network-alias=api"
            "--stop-timeout=600"
          ];
          networks = [ "traefik" ];
          volumes = [
            "${root}:/var/games/minecraft"
            "${root}/data:/app/data"
            "/var/run/docker.sock:/var/run/docker.sock"
          ];
        };
        mineos-web = {
          image = lib.mkDefault "ghcr.io/freeman412/mineos-web:latest";
          pull = lib.mkDefault "always";
          environmentFiles = [ environmentFile ];
          environment = lib.mapAttrs (_: lib.mkDefault) {
            NODE_ENV = "production";
            PRIVATE_API_BASE_URL = "http://api:5078";
            HOST = "0.0.0.0";
            PORT = "3000";
            WEB_PORT = "3000";
            PUBLIC_API_BASE_URL = "";
            PUBLIC_MINECRAFT_HOST = s.hostname;
            PUBLIC_MC_PORT_RANGE = "25500-25600";
            ORIGIN = origin;
            BODY_SIZE_LIMIT = "Infinity";
          };
          autoRemoveOnStop = false;
          extraOptions = [
            "--restart=unless-stopped"
            "--network-alias=web"
          ];
          dependsOn = [ "mineos-api" ];
          networks = [ "traefik" ];
        };
      };
    })
  ];
}
