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
  };
in
{
  imports = [ ./nixos.nix ];
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
      assertions = [
        {
          assertion =
            lib.attrByPath [ selected.hostname "mailserver" "enable" ] false config.modules.public-services
            && ps.isLocal config config.modules.public-services.${selected.hostname}.mailserver;
          message = "groupware: the same hostname must have an enabled local mailserver deployment.";
        }
      ];
    })
  ];
}
