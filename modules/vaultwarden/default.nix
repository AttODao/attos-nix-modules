{
  config,
  lib,
  pkgs,
  ...
}:
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
      signupsAllowed = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Allow password-based self-registration. Before each start, atomically enforce signups_allowed in /data/config.json. False also clears the signup-domain whitelist in persisted config and environment because it overrides the flag; true preserves any existing whitelist. Credentials, invitation/SSO-specific settings and other fields are preserved.";
      };
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
        preStart = lib.mkBefore ''
          ${pkgs.python3}/bin/python3 ${./patch-signups.py} \
            ${lib.escapeShellArg "${root}/vw-data/config.json"} \
            ${lib.boolToString s.cfg.signupsAllowed}
        '';
      };

      virtualisation.oci-containers.containers.vaultwarden = {
        # Update version and registry index digest together after release review.
        image = lib.mkDefault "vaultwarden/server:1.37.4@sha256:efb3cde962015fcc036b2ea625242248611943b27212ebf4392841fb30fad055";
        ports = lib.mkDefault (lib.optional s.standalone "127.0.0.1:8000:80");
        pull = lib.mkDefault "always";
        environmentFiles = lib.mkDefault [ environmentFile ];
        environment = lib.mapAttrs (_: lib.mkDefault) (
          {
            TZ = "Asia/Tokyo";
            SIGNUPS_ALLOWED = lib.boolToString s.cfg.signupsAllowed;
          }
          // lib.optionalAttrs (!s.cfg.signupsAllowed) {
            SIGNUPS_DOMAINS_WHITELIST = "";
          }
        );
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
