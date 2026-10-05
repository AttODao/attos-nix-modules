{
  config,
  lib,
  pkgs,
  ...
}:
let
  ps = import ../public-services/lib.nix { inherit lib; };
  s = ps.select config "opencloud";
  root = ps.require "opencloud" "dataDir" s.cfg.dataDir;
  environmentFile = ps.require "opencloud" "environmentFile" s.cfg.environmentFile;
  uid = toString (ps.require "opencloud" "uid" s.cfg.uid);
  gid = toString (ps.require "opencloud" "gid" s.cfg.gid);
  configDir = "${root}/config";
  dataDir = "${root}/data";
in
{
  imports = [
    ../docker
    ../swarm
  ];

  options.modules.public-services = ps.option "opencloud" (
    ps.common "OpenCloud server" "http://opencloud:9200"
    // {
      dataDir = ps.pathOption "Service root containing the existing config and data directories.";
      environmentFile = ps.pathOption "Runtime OpenCloud environment file, including credentials.";
      uid = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.unsigned;
        default = null;
        description = "Consumer-selected numeric owner and container UID for existing OpenCloud data.";
      };
      gid = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.unsigned;
        default = null;
        description = "Consumer-selected numeric owner and container GID for existing OpenCloud data.";
      };
    }
  );

  config = lib.mkMerge [
    { assertions = s.assertions; }
    (lib.mkIf s.enabled {
      modules.docker.enable = true;
      modules.swarm.enable = true;

      systemd.tmpfiles.rules = [
        "d ${builtins.toJSON root} 0700 root root -"
        "d ${builtins.toJSON configDir} 0700 ${uid} ${gid} -"
        "d ${builtins.toJSON dataDir} 0700 ${uid} ${gid} -"
      ];
      systemd.services.opencloud-prepare = {
        unitConfig.RequiresMountsFor = [ root ];
        serviceConfig.Type = "oneshot";
        script = ''
          set -eu
          ${pkgs.coreutils}/bin/install -d -m 0700 -o root -g root ${lib.escapeShellArg root}
          ${pkgs.coreutils}/bin/install -d -m 0700 -o ${uid} -g ${gid} ${lib.escapeShellArg configDir}
          ${pkgs.coreutils}/bin/install -d -m 0700 -o ${uid} -g ${gid} ${lib.escapeShellArg dataDir}
        '';
      };
      systemd.services.docker-opencloud = {
        unitConfig.RequiresMountsFor = [
          root
          environmentFile
        ];
        wants = [
          "docker-network-traefik.service"
          "opencloud-prepare.service"
        ];
        after = [
          "docker-network-traefik.service"
          "opencloud-prepare.service"
        ];
      };

      virtualisation.oci-containers.containers.opencloud = {
        image = lib.mkDefault "opencloudeu/opencloud-rolling:latest";
        pull = lib.mkDefault "always";
        user = lib.mkDefault "${uid}:${gid}";
        entrypoint = "/bin/sh";
        # Keep init non-interactive without disabling certificate verification.
        cmd = [
          "-c"
          "printf 'no\\n' | opencloud init || true; exec opencloud server"
        ];
        environment = lib.mapAttrs (_: lib.mkDefault) {
          OC_URL = "https://${s.hostname}";
          PROXY_HTTP_ADDR = "0.0.0.0:9200";
          PROXY_TLS = "false";
          OC_CONFIG_DIR = "/etc/opencloud";
          OC_DATA_DIR = "/var/lib/opencloud";
          OC_SHARING_PUBLIC_SHARE_MUST_HAVE_PASSWORD = "false";
          TZ = "Asia/Tokyo";
        };
        environmentFiles = [ environmentFile ];
        autoRemoveOnStop = false;
        extraOptions = [ "--restart=always" ];
        volumes = [
          "${configDir}:/etc/opencloud"
          "${dataDir}:/var/lib/opencloud"
          "/etc/localtime:/etc/localtime:ro"
        ];
        networks = [ "traefik" ];
      };
    })
  ];
}
