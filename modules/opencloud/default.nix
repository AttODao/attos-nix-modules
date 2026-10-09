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

  options.modules = ps.moduleOptions "opencloud" (
    ps.common "OpenCloud server"
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
      modules.swarm.enable = lib.mkIf (!s.standalone) true;

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
          (ps.networkUnit s)
          "opencloud-prepare.service"
        ];
        after = [
          (ps.networkUnit s)
          "opencloud-prepare.service"
        ];
      };

      virtualisation.oci-containers.containers.opencloud = {
        # Update version and registry index digest together after release review.
        image = lib.mkDefault "opencloudeu/opencloud-rolling:8.1.0@sha256:8fc64ca861739cc62095cd558814f2eba6a90acf5998d884e439b33a47875da8";
        ports = lib.mkDefault (lib.optional s.standalone "127.0.0.1:9200:9200");
        pull = lib.mkDefault "always";
        user = lib.mkDefault "${uid}:${gid}";
        entrypoint = lib.mkDefault "/bin/sh";
        # Keep init non-interactive without disabling certificate verification.
        cmd = lib.mkDefault [
          "-c"
          "printf 'no\\n' | opencloud init || true; exec opencloud server"
        ];
        environment = lib.mapAttrs (_: lib.mkDefault) {
          OC_URL = ps.url s 9200;
          PROXY_HTTP_ADDR = "0.0.0.0:9200";
          PROXY_TLS = "false";
          OC_CONFIG_DIR = "/etc/opencloud";
          OC_DATA_DIR = "/var/lib/opencloud";
          OC_SHARING_PUBLIC_SHARE_MUST_HAVE_PASSWORD = "false";
          TZ = "Asia/Tokyo";
        };
        environmentFiles = lib.mkDefault [ environmentFile ];
        autoRemoveOnStop = lib.mkDefault false;
        extraOptions = lib.mkDefault [ "--restart=always" ];
        volumes = lib.mkDefault [
          "${configDir}:/etc/opencloud"
          "${dataDir}:/var/lib/opencloud"
          "/etc/localtime:/etc/localtime:ro"
        ];
        networks = lib.mkDefault [ (ps.network s) ];
      };
    })
  ];
}
