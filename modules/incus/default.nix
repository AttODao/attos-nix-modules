{
  lib,
  options,
  pkgs,
  ...
}:
let
  json = pkgs.formats.json { };
  ps = import ../public-services/lib.nix { inherit lib; };
in
{
  imports = [ ./nixos.nix ];

  options.modules.incus = {
    enable = lib.mkEnableOption "shared Incus create-only provisioning";
    preseed = lib.mkOption {
      inherit (options.virtualisation.incus.preseed) type default;
      description = "Native Incus bootstrap configuration. Exactly one named storage pool is required; an existing pool skips all bootstrap, without reconciliation.";
    };
    initrdKernelModules = lib.mkOption {
      type = options.boot.initrd.kernelModules.type;
      default = [ ];
      description = "Kernel modules loaded in initrd when Incus is enabled.";
    };
    preseedKernelModules = lib.mkOption {
      type = lib.types.listOf lib.types.nonEmptyStr;
      default = [ ];
      description = "Kernel modules loaded with modprobe before a non-skipped Incus preseed run.";
    };
    provisionKernelModules = lib.mkOption {
      type = lib.types.listOf lib.types.nonEmptyStr;
      default = [ ];
      description = "Kernel modules loaded with modprobe before container provisioning.";
    };
    stateDir = ps.pathOption "Persistent image-source stamp directory; required when containers are declared. Existing directories are never cleared.";
    rebuild.flakeFile = ps.pathOption "Absolute runtime path to a flake.nix checkout. Non-null installs container-rebuild for the declared container names; nixosConfigurations must use those same names. The checkout is not copied into the package.";

    containers = lib.mkOption {
      default = { };
      description = ''
        Explicit images and native launch configuration for missing instances.
        Existing instances keep their launch configuration; removed entries are
        not deleted. Image aliases are server-dotfiles-<name>. Image source
        paths, not mutable file contents, key the cache.
      '';
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
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
