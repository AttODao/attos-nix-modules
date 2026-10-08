{ config, lib, ... }:
let
  ps = import ../public-services/lib.nix { inherit lib; };
  s = ps.select config "mineos";
  root = ps.require "mineos" "dataDir" s.cfg.dataDir;
  environmentFile = ps.require "mineos" "environmentFile" s.cfg.environmentFile;
  uid = toString (ps.require "mineos" "uid" s.cfg.uid);
  gid = toString (ps.require "mineos" "gid" s.cfg.gid);
  origin = ps.url s 3002;
in
{
  imports = [
    ../docker
    ../swarm
  ];

  options.modules = ps.moduleOptions "mineos" (
    ps.common "MineOS Minecraft management"
    // {
      dataDir = ps.pathOption "Service root containing data, archives, backups, imports, profiles and servers.";
      environmentFile = ps.pathOption "Runtime MineOS environment file containing credentials.";
      tcpPorts = lib.mkOption {
        type = lib.types.listOf lib.types.port;
        default = lib.range 25500 25600;
        description = "Minecraft TCP ports forwarded by Traefik or published on loopback when standalone; override allocation separately through standard MineOS environment settings if needed.";
      };
      udpPorts = lib.mkOption {
        type = lib.types.listOf lib.types.port;
        default = lib.range 19132 19137;
        description = "Bedrock UDP ports forwarded by Traefik or published on loopback when standalone. Private public services must disable these and arrange VPN-only ingress in the consumer.";
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
      modules.swarm.enable = lib.mkIf (!s.standalone) true;

      systemd.services.docker-mineos-api = {
        unitConfig.RequiresMountsFor = [
          root
          environmentFile
        ];
        wants = [ (ps.networkUnit s) ];
        after = [ (ps.networkUnit s) ];
        serviceConfig.TimeoutStopSec = lib.mkDefault "10min";
      };
      systemd.services.docker-mineos-web = {
        unitConfig.RequiresMountsFor = [
          root
          environmentFile
        ];
        wants = [ (ps.networkUnit s) ];
        after = [
          (ps.networkUnit s)
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
          ports = lib.mkDefault (
            lib.optionals s.standalone (
              map (port: "127.0.0.1:${toString port}:${toString port}/tcp") s.cfg.tcpPorts
              ++ map (port: "127.0.0.1:${toString port}:${toString port}/udp") s.cfg.udpPorts
            )
          );
          pull = lib.mkDefault "always";
          environmentFiles = lib.mkDefault [ environmentFile ];
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
          autoRemoveOnStop = lib.mkDefault false;
          extraOptions = lib.mkDefault [
            "--restart=unless-stopped"
            "--network-alias=api"
            "--stop-timeout=600"
          ];
          networks = lib.mkDefault [ (ps.network s) ];
          volumes = lib.mkDefault [
            "${root}:/var/games/minecraft"
            "${root}/data:/app/data"
            "/var/run/docker.sock:/var/run/docker.sock"
          ];
        };
        mineos-web = {
          image = lib.mkDefault "ghcr.io/freeman412/mineos-web:latest";
          ports = lib.mkDefault (lib.optional s.standalone "127.0.0.1:3002:3000");
          pull = lib.mkDefault "always";
          environmentFiles = lib.mkDefault [ environmentFile ];
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
          autoRemoveOnStop = lib.mkDefault false;
          extraOptions = lib.mkDefault [
            "--restart=unless-stopped"
            "--network-alias=web"
          ];
          dependsOn = [ "mineos-api" ];
          networks = lib.mkDefault [ (ps.network s) ];
        };
      };
    })
  ];
}
