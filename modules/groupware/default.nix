{ config, lib, ... }:
let
  ps = import ../public-services/lib.nix { inherit lib; };
  selected = ps.select config "groupware";
  serviceOptions = ps.common "shared Roundcube and Radicale groupware" // {
    backendUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.nonEmptyStr;
      default = null;
      description = "Native nginx upstream reachable by the gateway; required when Traefik forwards this service. Do not use Docker's own loopback address.";
    };
    dataDir = ps.pathOption "Consumer-owned Radicale data directory (collections and generated runtime authentication).";
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
