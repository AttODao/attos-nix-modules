{ lib, pkgs, ... }:
let
  json = pkgs.formats.json { };
  ps = import ../public-services/lib.nix { inherit lib; };
in
{
  imports = [ ./nixos.nix ];

  options.modules.incus = {
    enable = lib.mkEnableOption "shared Incus create-only provisioning";
    stateDir = ps.pathOption "Persistent image-source stamp directory; required when containers are declared. Existing directories are never cleared.";

    initializePool = lib.mkOption {
      type = lib.types.nullOr lib.types.nonEmptyStr;
      default = null;
      description = ''
        Pool whose presence skips native Incus preseed. Required when preseed is
        supplied, and must be declared in its storage_pools. This is only an
        initialize-once guard: an existing pool does not prove that networks,
        profiles or other bootstrap resources are complete. Existing/partial
        initialization is not repaired or overwritten.
      '';
    };

    containers = lib.mkOption {
      default = { };
      description = ''
        Explicit images and native launch configuration for missing instances.
        Existing instances keep their launch configuration; removed entries are
        not deleted. Image source paths, not mutable file contents, key the cache.
      '';
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            alias = lib.mkOption {
              type = lib.types.nonEmptyStr;
              description = "Local Incus image alias (not a remote reference).";
            };
            metadata = lib.mkOption {
              type = lib.types.path;
              description = "Metadata archive, or image output containing tarball/*.tar.xz.";
            };
            rootfs = lib.mkOption {
              type = lib.types.path;
              description = "Rootfs archive, or image output containing one *.squashfs.";
            };
            launchConfig = lib.mkOption {
              type = lib.types.attrsOf json.type;
              description = ''
                Native Incus launch stdin configuration, including any profiles,
                config and devices. No privilege, disk or network defaults are added.
                This is used only when creating a missing instance.
              '';
            };
            managedDeviceNames = lib.mkOption {
              type = lib.types.listOf lib.types.nonEmptyStr;
              default = [ ];
              description = ''
                Opt-in devices from launchConfig.devices to upsert on every run.
                Existing devices receive only the supplied non-type properties:
                their type and omitted properties are not reconciled. Devices
                outside this list, including removed entries, are left alone.
              '';
            };
          };
        }
      );
    };
  };
}
