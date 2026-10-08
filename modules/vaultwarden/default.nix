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

  options.modules = ps.moduleOptions "vaultwarden" (
    ps.common "Vaultwarden password manager"
    // {
      dataDir = ps.pathOption "Service root containing the existing vw-data directory.";
      environmentFile = ps.pathOption "Runtime environment file containing Vaultwarden credentials and mail configuration.";
      extraHosts = lib.mkOption {
        type = lib.types.attrsOf lib.types.nonEmptyStr;
        default = { };
        description = "Additional container hostname-to-address mappings, for example an SMTP gateway on a private link.";
      };
    }
  );

  config = lib.mkMerge [
    { assertions = s.assertions; }
    (lib.mkIf s.enabled {
      modules.docker.enable = true;
      modules.swarm.enable = lib.mkIf (!s.standalone) true;

      systemd.tmpfiles.rules = [
        "d ${builtins.toJSON root} 0755 root root -"
        "d ${builtins.toJSON "${root}/vw-data"} 0700 root root -"
      ];
      systemd.services.docker-vaultwarden = {
        unitConfig.RequiresMountsFor = [
          root
          environmentFile
        ];
        wants = [ (ps.networkUnit s) ];
        after = [ (ps.networkUnit s) ];
      };

      virtualisation.oci-containers.containers.vaultwarden = {
        image = lib.mkDefault "vaultwarden/server:latest";
        ports = lib.mkDefault (lib.optional s.standalone "127.0.0.1:8000:80");
        pull = lib.mkDefault "always";
        environmentFiles = lib.mkDefault [ environmentFile ];
        environment.TZ = lib.mkDefault "Asia/Tokyo";
        autoRemoveOnStop = lib.mkDefault false;
        extraOptions = lib.mkDefault (
          [ "--restart=unless-stopped" ]
          ++ lib.mapAttrsToList (host: address: "--add-host=${host}:${address}") s.cfg.extraHosts
        );
        volumes = lib.mkDefault [ "${root}/vw-data:/data" ];
        networks = lib.mkDefault [ (ps.network s) ];
      };
    })
  ];
}
