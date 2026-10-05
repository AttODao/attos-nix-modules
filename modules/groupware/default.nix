{ config, lib, ... }:
let
  ps = import ../public-services/lib.nix { inherit lib; };
  selected = ps.select config "groupware";
  mailHost =
    if !selected.enabled then
      ""
    else if selected.cfg.mailserverHostName == null then
      selected.hostname
    else
      selected.cfg.mailserverHostName;
  serviceOptions = ps.common "shared Roundcube and Radicale groupware" "http://localhost" // {
    backendUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.nonEmptyStr;
      default = null;
      description = "Native nginx upstream reachable by the gateway; required when Traefik forwards this service. Do not use Docker's own loopback address.";
    };
    dataDir = ps.pathOption "Consumer-owned Radicale data directory (collections and generated runtime authentication).";
    mailserverHostName = lib.mkOption {
      type = lib.types.nullOr lib.types.nonEmptyStr;
      default = null;
      description = "Hostname of an enabled local mailserver. Null enables the same-hostname mailserver dependency; other hostnames must be enabled explicitly.";
    };
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
          config.mailserver.enable = lib.mkIf (
            config.groupware.enable && config.groupware.deploy && config.groupware.mailserverHostName == null
          ) true;
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
            lib.attrByPath [ mailHost "mailserver" "enable" ] false config.modules.public-services
            && lib.attrByPath [ mailHost "mailserver" "deploy" ] false config.modules.public-services;
          message = "groupware: mailserverHostName must refer to an enabled local mailserver deployment.";
        }
      ];
    })
  ];
}
