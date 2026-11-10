{
  config,
  lib,
  ps,
  ...
}:
let
  s = ps.select config "vaultwarden";
  root = ps.require "vaultwarden" "dataDir" s.cfg.dataDir;
  dataFolder = "${root}/vw-data";
  environmentFile = ps.require "vaultwarden" "environmentFile" s.cfg.environmentFile;
  listen = ps.listen s 8000;
in
{
  options.modules = ps.moduleOptions "vaultwarden" (
    ps.common "Vaultwarden password manager"
    // {
      dataDir = ps.pathOption "Service root whose vw-data/ directory is DATA_FOLDER (created when missing); required when deployed locally.";
      environmentFile = ps.pathOption "Runtime environment file with Vaultwarden credentials (for example ADMIN_TOKEN) and SMTP settings; required when deployed locally. It is read after the generated settings, so its values win.";
      signupsAllowed = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "SIGNUPS_ALLOWED: allow self-registration. False also sets an empty SIGNUPS_DOMAINS_WHITELIST, since a whitelist admits its domains even with signups off; true leaves the whitelist unset. The environment file is read last and can still set either.";
      };
      extraHosts = lib.mkOption {
        type = lib.types.attrsOf lib.types.nonEmptyStr;
        default = { };
        description = "Additional hostname-to-address mappings added to the host's /etc/hosts, for example an SMTP gateway on a private link.";
      };
    }
  );

  config = lib.mkMerge [
    { assertions = s.assertions; }
    (lib.mkIf s.enabled {
      systemd.tmpfiles.rules = [
        "d ${builtins.toJSON root} 0755 root root -"
        "d ${builtins.toJSON dataFolder} 0700 vaultwarden vaultwarden -"
      ];
      networking.hosts = lib.mapAttrs' (
        host: address: lib.nameValuePair address [ host ]
      ) s.cfg.extraHosts;

      services.vaultwarden = {
        enable = true;
        environmentFile = [ environmentFile ];
        config = lib.mapAttrs (_: lib.mkDefault) (
          {
            DATA_FOLDER = dataFolder;
            ROCKET_ADDRESS = listen.address;
            ROCKET_PORT = listen.port;
            # Ignore any saved config.json so Nix and the environment file stay authoritative.
            CONFIG_FILE = "/dev/null/config.json";
            DOMAIN = ps.url s 8000;
            SIGNUPS_ALLOWED = s.cfg.signupsAllowed;
          }
          // lib.optionalAttrs (!s.cfg.signupsAllowed) {
            SIGNUPS_DOMAINS_WHITELIST = "";
          }
        );
      };
      networking.firewall = ps.backendFirewall config s [ ];
      systemd.services.vaultwarden = {
        unitConfig.RequiresMountsFor = [
          root
          environmentFile
        ];
        serviceConfig.ReadWritePaths = [ dataFolder ];
      };
    })
  ];
}
