{
  config,
  lib,
  ...
}:
let
  ps = import ../public-services/lib.nix { inherit lib; };
  s = ps.select config "immich";
in
{
  config = lib.mkIf s.enabled (
    let
      root = ps.require "immich" "dataDir" s.cfg.dataDir;
      environmentFile = ps.require "immich" "environmentFile" s.cfg.environmentFile;
      directory = mode: owner: {
        mode = lib.mkDefault mode;
        user = lib.mkDefault owner;
        group = lib.mkDefault owner;
      };
      mounts.unitConfig.RequiresMountsFor = lib.mkDefault [ root ];
    in
    {
      modules.docker.networks.immich = { };

      # Keep both inputs required even if standard OCI defaults are overridden.
      assertions = [
        {
          assertion = root != null && environmentFile != null;
          message = "Immich requires dataDir and environmentFile for local deployment.";
        }
      ];

      systemd.tmpfiles.settings."10-immich" = {
        "${root}".d = directory "0755" "root";
        "${root}/library".d = directory "0755" "root";
        # Postgres and Valkey run as UID/GID 999 and own their mounted data roots.
        "${root}/postgres".d = directory "0700" "999";
        "${root}/redis".d = directory "0700" "999";
        "${root}/model-cache".d = directory "0755" "root";
      };

      systemd.services = {
        docker-immich-database = mounts;
        docker-immich-machine-learning = mounts;
        docker-immich-redis = mounts;
        docker-immich-server = mounts;
      };

      virtualisation.oci-containers.containers = {
        immich-database = {
          image = lib.mkDefault "ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0@sha256:bcf63357191b76a916ae5eb93464d65c07511da41e3bf7a8416db519b40b1c23";
          environmentFiles = lib.mkDefault [ environmentFile ];
          autoRemoveOnStop = lib.mkDefault false;
          extraOptions = lib.mkDefault [
            "--restart=unless-stopped"
            "--network-alias=database"
            "--shm-size=128mb"
          ];
          volumes = lib.mkDefault [ "${root}/postgres:/var/lib/postgresql/data" ];
          networks = lib.mkDefault [ "immich" ];
        };

        immich-machine-learning = {
          image = lib.mkDefault "ghcr.io/immich-app/immich-machine-learning:v3.3.3@sha256:73915f07e1f4289ba45b174c58443db74cef47ddf502613f475fc5e52458ea42";
          environmentFiles = lib.mkDefault [ environmentFile ];
          autoRemoveOnStop = lib.mkDefault false;
          extraOptions = lib.mkDefault [ "--restart=unless-stopped" ];
          volumes = lib.mkDefault [ "${root}/model-cache:/cache" ];
          networks = lib.mkDefault [ "immich" ];
        };

        immich-redis = {
          image = lib.mkDefault "docker.io/valkey/valkey:9.1.2@sha256:418652cfb58ef879d4978c33553735d7147016032d5aefaa14c828e611eb9dfd";
          volumes = lib.mkDefault [ "${root}/redis:/data" ];
          autoRemoveOnStop = lib.mkDefault false;
          extraOptions = lib.mkDefault [
            "--restart=unless-stopped"
            "--network-alias=redis"
          ];
          networks = lib.mkDefault [ "immich" ];
        };

        immich-server = {
          image = lib.mkDefault "ghcr.io/immich-app/immich-server:v3.3.3@sha256:bae7664ff3aa4c2c1fcbdcdd86b40b105643c5f861f3e6a770fc760089f25862";
          ports = lib.mkDefault (ps.publish s 2283 2283);
          environmentFiles = lib.mkDefault [ environmentFile ];
          autoRemoveOnStop = lib.mkDefault false;
          extraOptions = lib.mkDefault [ "--restart=unless-stopped" ];
          volumes = lib.mkDefault [
            "/etc/localtime:/etc/localtime:ro"
            "${root}/library:/data"
          ];
          dependsOn = lib.mkDefault [
            "immich-database"
            "immich-redis"
          ];
          networks = lib.mkDefault [
            "immich"
          ];
        };
      };
    }
  );
}
