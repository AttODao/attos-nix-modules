{
  config,
  lib,
  pkgs,
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
      ensureNetwork =
        lib.replaceStrings [ "@docker@" ] [ (lib.escapeShellArg "${pkgs.docker}/bin/docker") ]
          (builtins.readFile ./ensure-network.sh);
      directory = mode: {
        mode = lib.mkDefault mode;
        user = lib.mkDefault "root";
        group = lib.mkDefault "root";
      };
      networkDep = {
        unitConfig.RequiresMountsFor = lib.mkDefault [ root ];
        requires = [ "docker-network-immich.service" ];
        after = [ "docker-network-immich.service" ];
        # The persistent oneshot can outlive a network removed by Docker prune.
        preStart = lib.mkBefore ensureNetwork;
      };
    in
    {
      # Keep both inputs required even if standard OCI defaults are overridden.
      assertions = [
        {
          assertion = root != null && environmentFile != null;
          message = "Immich requires dataDir and environmentFile for local deployment.";
        }
      ];

      systemd.tmpfiles.settings."10-immich" = {
        "${root}".d = directory "0755";
        "${root}/library".d = directory "0755";
        "${root}/postgres".d = directory "0755";
        "${root}/redis".d = directory "0700";
        "${root}/model-cache".d = directory "0755";
      };

      systemd.services = {
        docker-network-immich = {
          description = lib.mkDefault "Create docker network immich";
          wantedBy = lib.mkDefault [ "multi-user.target" ];
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
        docker-immich-database = networkDep;
        docker-immich-machine-learning = networkDep;
        docker-immich-redis = networkDep;
        docker-immich-server = lib.mkMerge [
          networkDep
          {
            wants = [ "docker-network-traefik.service" ];
            after = [ "docker-network-traefik.service" ];
          }
        ];
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
          image = lib.mkDefault "ghcr.io/immich-app/immich-machine-learning:v3.2.4@sha256:e16c2f166a8174901959fdf85e2e4c7bd1ebc4b37e0b6655de97c41408a260c4";
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
          image = lib.mkDefault "ghcr.io/immich-app/immich-server:v3.2.4@sha256:d317916b28090c33eb36b308464ea391f8b7df1d850fcfea227a39ec879718c2";
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
            "traefik"
          ];
        };
      };
    }
  );
}
