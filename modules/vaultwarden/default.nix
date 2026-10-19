{
  config,
  lib,
  ...
}:
let
  ps = import ../public-services/lib.nix { inherit lib; };
  s = ps.select config "vaultwarden";
  root = ps.require "vaultwarden" "dataDir" s.cfg.dataDir;
  dataFolder = "${root}/vw-data";
  environmentFile = ps.require "vaultwarden" "environmentFile" s.cfg.environmentFile;
  listen =
    if s.standalone then
      {
        address = "127.0.0.1";
        port = "8000";
      }
    else
      ps.backendEndpoint s;
in
{
  options.modules = ps.moduleOptions "vaultwarden" (
    ps.common "Vaultwarden password manager"
    // {
      dataDir = ps.pathOption "Service root containing the existing vw-data directory.";
      environmentFile = ps.pathOption "Runtime environment file containing Vaultwarden credentials and mail configuration.";
      signupsAllowed = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Allow password-based self-registration. False also clears the signup-domain whitelist because it overrides the flag; true preserves any whitelist from the environment file.";
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
            ROCKET_ADDRESS = lib.removeSuffix "]" (lib.removePrefix "[" listen.address);
            ROCKET_PORT = lib.toInt listen.port;
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
