{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.modules.incus;
  native = config.virtualisation.incus;
  ps = import ../public-services/lib.nix { inherit lib; };
  manifest = pkgs.writeText "incus-containers.json" (
    builtins.toJSON {
      containers = lib.mapAttrs (_: instance: {
        inherit (instance) alias launchConfig managedDeviceNames;
        metadata = toString instance.metadata;
        rootfs = toString instance.rootfs;
      }) cfg.containers;
    }
  );
  runner = pkgs.writeShellApplication {
    name = "attos-incus";
    runtimeInputs = [
      native.clientPackage
      pkgs.python3
    ];
    text = ''exec python3 ${./provision.py} "$@"'';
  };
  preseed = native.preseed != null;
  pools = if !preseed then [ ] else native.preseed.storage_pools or [ ];
in
{
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        virtualisation.incus.enable = true;
        networking.nftables.enable = lib.mkDefault true;
        assertions = [
          {
            assertion =
              !preseed
              || (cfg.initializePool != null && lib.any (pool: (pool.name or null) == cfg.initializePool) pools);
            message = "modules.incus.initializePool must name a storage pool in the consumer's Incus preseed; initialization is create-only.";
          }
        ];
      }
      (lib.mkIf preseed {
        systemd.services.incus-preseed = {
          restartIfChanged = false;
          serviceConfig.ExecCondition = [
            "${runner}/bin/attos-incus condition ${
              lib.escapeShellArg (ps.require "modules.incus" "initializePool" cfg.initializePool)
            }"
          ];
        };
      })
      (lib.mkIf (cfg.containers != { }) {
        systemd.services.incus-containers = {
          description = "Import explicit Incus images and create missing instances";
          wantedBy = [ "multi-user.target" ];
          after = [
            "incus.service"
            "network-online.target"
          ]
          ++ lib.optional preseed "incus-preseed.service";
          wants = [ "network-online.target" ];
          requires = [ "incus.service" ] ++ lib.optional preseed "incus-preseed.service";
          restartTriggers = [ manifest ];
          unitConfig.RequiresMountsFor = [ (ps.require "modules.incus" "stateDir" cfg.stateDir) ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart = "${runner}/bin/attos-incus provision ${manifest} ${
              lib.escapeShellArg (ps.require "modules.incus" "stateDir" cfg.stateDir)
            }";
            UMask = "0077";
          };
        };
      })
    ]
  );
}
