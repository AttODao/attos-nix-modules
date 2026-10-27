{
  config,
  lib,
  ps,
  ...
}:
let
  s = ps.select config "attos-hoyo-dashboard";
in
{
  config = lib.mkIf s.enabled (
    let
      root = ps.require "attos-hoyo-dashboard" "dataDir" s.cfg.dataDir;
      environmentFile = ps.require "attos-hoyo-dashboard" "environmentFile" s.cfg.environmentFile;
      # Initial role/database names; changing them later does not migrate an existing DB.
      database = {
        DB_NAME = "attos_dashboard";
        DB_USER = "attos_dashboard";
      };
      mounts.unitConfig.RequiresMountsFor = lib.mkDefault [ root ];
    in
    {
      modules.docker.networks.attos-hoyo-dashboard = { };

      systemd.tmpfiles.settings."10-attos-hoyo-dashboard" = {
        "${root}".d = {
          mode = lib.mkDefault "0755";
          user = lib.mkDefault "root";
          group = lib.mkDefault "root";
        };
        # The postgres entrypoint creates and owns PGDATA below this mount.
        "${root}/postgres".d = {
          mode = lib.mkDefault "0755";
          user = lib.mkDefault "root";
          group = lib.mkDefault "root";
        };
      };

      systemd.services = {
        docker-attos-hoyo-dashboard-db = mounts;
      };

      virtualisation.oci-containers.containers = {
        attos-hoyo-dashboard-db = {
          image = lib.mkDefault "docker.io/library/postgres:18-alpine3.23@sha256:dec395d8c09c45609d6deb5c2388a07882d64fa59b1d98c1895792e085f57888";
          # The app connects as the image-created POSTGRES_USER, which is a superuser.
          environmentFiles = lib.mkDefault [ environmentFile ];
          environment = lib.mapAttrs (_: lib.mkDefault) {
            POSTGRES_USER = database.DB_USER;
            POSTGRES_DB = database.DB_NAME;
          };
          autoRemoveOnStop = lib.mkDefault false;
          extraOptions = lib.mkDefault [
            "--restart=unless-stopped"
            "--network-alias=db"
          ];
          volumes = lib.mkDefault [
            "${root}/postgres:/var/lib/postgresql"
          ];
          networks = lib.mkDefault [ "attos-hoyo-dashboard" ];
        };

        attos-hoyo-dashboard = {
          # Update version and registry index digest together after release review.
          image = lib.mkDefault "git.attodao.cc/attodao/attoshoyodashboard:1.5.0@sha256:93d729a8570f533d811ce3a06d7bcd92b2d98f7d305bb7945c68c0b4cbe043b0";
          ports = lib.mkDefault (ps.publish s 8082 8080);
          environmentFiles = lib.mkDefault (
            [ environmentFile ]
            ++ lib.optional (s.cfg.metricsEnvironmentFile != null) s.cfg.metricsEnvironmentFile
          );
          environment = lib.mapAttrs (_: lib.mkDefault) (
            database
            // {
              DB_HOST = "db";
              DB_PORT = "5432";
              BIND_ADDR = "0.0.0.0:8080";
              INITIAL_ADMIN_USERNAME = s.cfg.initialAdminUsername;
              PUBLIC_ORIGIN = ps.url s 8082;
              RP_ID = s.hostname;
              SESSION_TTL_DAYS = "7";
              TIMEZONE_OFFSET = ps.require "attos-hoyo-dashboard" "timezoneOffset" s.cfg.timezoneOffset;
            }
          );
          autoRemoveOnStop = lib.mkDefault false;
          # Startup fails until PostgreSQL accepts connections; the restart policy retries.
          extraOptions = lib.mkDefault [
            "--restart=unless-stopped"
            "--network-alias=attos-hoyo-dashboard"
          ];
          dependsOn = lib.mkDefault [ "attos-hoyo-dashboard-db" ];
          networks = lib.mkDefault [
            "attos-hoyo-dashboard"
          ];
        };
      };
    }
  );
}
