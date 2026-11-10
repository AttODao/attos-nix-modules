{
  config,
  lib,
  ps,
  ...
}:
let
  selected = ps.select config "groupware";
  serviceOptions = ps.common "shared Roundcube and Radicale groupware" // {
    backendUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.nonEmptyStr;
      default = null;
      description = "HTTP upstream of this host's nginx (Roundcube and /radicale/) reachable by the gateway, for example http://10.0.0.2:80; required when enabled. nginx keeps its native listen addresses (all addresses); the consumer admits the gateway to that port in its own firewall.";
    };
    dataDir = ps.pathOption "Consumer-owned Radicale data directory for collections.";
    productName = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "Mail";
      description = "Roundcube product name displayed in the web interface.";
    };
  };
in
{
  imports = [ ./nixos.nix ];
  options.modules.groupware = lib.mkOption {
    type = lib.types.submodule (ps.standaloneOptions serviceOptions);
    default = { };
    description = "Standalone Roundcube and Radicale with local mailserver integration.";
  };
  options.modules.public-services = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule (
        { config, ... }: {
          options.groupware = serviceOptions;
          # Keep the dependency inside each hostname submodule, not a root registry scan.
          config.mailserver = lib.mkIf (config.groupware.enable && config.groupware.deploy) {
            enable = true;
            host = lib.mkDefault config.groupware.host;
          };
        }
      )
    );
  };
  config = lib.mkMerge [
    { assertions = selected.assertions; }
    (lib.mkIf selected.enabled {
      modules.mailserver.enable = lib.mkIf selected.standalone true;
      assertions = [
        {
          assertion =
            if selected.standalone then
              config.modules.mailserver.enable
            else
              lib.attrByPath [ selected.hostname "mailserver" "enable" ] false config.modules.public-services
              && ps.isLocal config config.modules.public-services.${selected.hostname}.mailserver;
          message = "groupware: the same hostname must have an enabled local mailserver deployment.";
        }
      ];
    })
  ];
}
