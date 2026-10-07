{ config, lib, ... }:
let
  ps = import ../public-services/lib.nix { inherit lib; };
  s = ps.select config "vaultwarden";
  root = ps.require "vaultwarden" "dataDir" s.cfg.dataDir;
  environmentFile = ps.require "vaultwarden" "environmentFile" s.cfg.environmentFile;
in
{
  imports = [
    ../docker
    ../swarm
  ];

  options.modules.public-services = ps.option "vaultwarden" (
    ps.common "Vaultwarden password manager"
    // {
      dataDir = ps.pathOption "Service root containing the existing vw-data directory.";
      environmentFile = ps.pathOption "Runtime environment file containing Vaultwarden credentials and mail configuration.";
    }
  );

  config = lib.mkMerge [
    { assertions = s.assertions; }
    (lib.mkIf s.enabled {
      modules.docker.enable = true;
      modules.swarm.enable = true;

      systemd.tmpfiles.rules = [
        "d ${builtins.toJSON root} 0755 root root -"
        "d ${builtins.toJSON "${root}/vw-data"} 0700 root root -"
      ];
      systemd.services.docker-vaultwarden = {
        unitConfig.RequiresMountsFor = [
          root
          environmentFile
        ];
        wants = [ "docker-network-traefik.service" ];
        after = [ "docker-network-traefik.service" ];
      };

      virtualisation.oci-containers.containers.vaultwarden = {
        image = lib.mkDefault "vaultwarden/server:latest";
        pull = lib.mkDefault "always";
        environmentFiles = lib.mkDefault [ environmentFile ];
        environment.TZ = lib.mkDefault "Asia/Tokyo";
        autoRemoveOnStop = lib.mkDefault false;
        extraOptions = lib.mkDefault [ "--restart=unless-stopped" ];
        volumes = lib.mkDefault [ "${root}/vw-data:/data" ];
        networks = lib.mkDefault [ "traefik" ];
      };
    })
  ];
}
