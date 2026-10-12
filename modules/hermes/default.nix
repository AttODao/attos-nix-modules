{ config, lib, ... }:
let
  ps = import ../public-services/lib.nix { inherit lib; };
  selected = ps.select config "hermes";
  ownership =
    description:
    lib.mkOption {
      type = lib.types.nullOr (lib.types.ints.between 1 65534);
      default = null;
      inherit description;
    };
in
{
  imports = [ ./nixos.nix ];

  options.modules = ps.moduleOptions "hermes" (
    ps.common "Hermes Agent dashboard with private password authentication"
    // {
      private = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Keep this management dashboard out of public CNAMEs and behind the gateway's private-network allowlist.";
      };
      dataDir = ps.pathOption "Writable persistent HERMES_HOME. Bootstrap config.yaml and .env at runtime; the module never writes application settings, credentials or history.";
      uid = ownership "Non-root UID of the consumer-owned service account, used for container execution and persistent directory ownership.";
      gid = ownership "Non-root GID of the consumer-owned service group.";
    }
  );

  config = lib.mkMerge [
    {
      assertions =
        selected.assertions
        ++ map (entry: {
          assertion = entry.cfg.private;
          message = "hermes: password-authenticated dashboards must remain private; use VPN access.";
        }) (ps.entries config "hermes");
    }
    (lib.mkIf selected.enabled {
      modules.docker.enable = true;
      modules.swarm.enable = lib.mkIf (!selected.standalone) true;
    })
  ];
}
