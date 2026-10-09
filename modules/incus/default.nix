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
    enable = lib.mkEnableOption "shared Incus KVM virtual-machine create-only provisioning";
    package = lib.mkOption {
      inherit (options.virtualisation.incus.package) type default;
      description = "Incus daemon package, using the native default (incus-lts). Select pkgs.incus for newer features such as native-context GPUs. The native client default follows this package.";
    };
    preseed = lib.mkOption {
      inherit (options.virtualisation.incus.preseed) type default;
      description = "Native Incus bootstrap configuration. Exactly one named storage pool is required; the existing target pool skips all bootstrap, without reconciliation. Other pools without the target fail closed until explicitly migrated.";
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
      description = "Kernel modules loaded with modprobe before virtual-machine provisioning.";
    };
    stateDir = ps.pathOption "Persistent image-source stamp directory; required when virtualMachines are declared. Existing directories are never cleared.";
    rebuild.flakeFile = ps.pathOption "Absolute runtime path to a flake.nix checkout. Non-null installs vm-rebuild for the declared VM names; nixosConfigurations must use those same names. The checkout is not copied into the package.";

    virtualMachines = lib.mkOption {
      default = { };
      description = ''
        Explicit qcow2 images and native launch configuration for missing KVM VMs.
        Existing VMs keep their launch configuration; a same-name container is an
        error, never converted or deleted. Removed entries are not deleted.
        Image aliases are server-dotfiles-<name>. Image source paths, not mutable
        file contents, key the cache.
      '';
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            metadata = lib.mkOption {
              type = lib.types.path;
              description = "Metadata archive, or image output containing tarball/*.tar.xz.";
            };
            disk = lib.mkOption {
              type = lib.types.path;
              description = "Qcow2 disk image, or image output containing one *.qcow2 (for example system.build.qemuImage or repartImage from the standard Incus VM image module).";
            };
            launchConfig = lib.mkOption {
              type = lib.types.attrsOf json.type;
              description = ''
                Native Incus launch stdin configuration, including any profiles,
                config and devices. No privilege, disk or network defaults are added.
                This is used only when creating a missing instance.
              '';
            };
            credentialFiles = lib.mkOption {
              type = lib.types.addCheck (lib.types.attrsOf ps.absolutePath) (
                files:
                lib.all (
                  destination:
                  ps.absolutePath.check destination
                  && !lib.hasSuffix "/" destination
                  && !lib.hasInfix "//" destination
                  && !lib.any (
                    part:
                    lib.elem part [
                      "."
                      ".."
                    ]
                  ) (lib.splitString "/" destination)
                  && !lib.elem (builtins.dirOf destination) [
                    "/"
                    "/etc"
                    "/root"
                    "/var"
                    "/var/lib"
                    "/var/cache"
                    "/var/log"
                    "/run"
                    "/home"
                    "/srv"
                    "/tmp"
                    "/usr"
                    "/opt"
                  ]
                ) (builtins.attrNames files)
              );
              default = { };
              description = "Guest absolute destination paths mapped to host runtime credential paths. Destination parents must be dedicated credential directories: missing ones are created root:root 0700; existing ones must already be root:root 0700 and are never chmod/chowned. Shared top-level/system parents and dot path segments are rejected. Each file is delivered to this VM only as root:root 0600 via local/default Incus, then atomically renamed. No contents or host Age identity are copied into images/store. Consumer owns secret supply and rotation.";
            };
            credentialRestartUnits = lib.mkOption {
              type = lib.types.listOf (lib.types.strMatching "[^[:space:]/]+\\.service");
              default = [ ];
              description = "Guest service units restarted after all credentialFiles are delivered. Rotation must restart incus-vm-credentials-<name>.service on the host.";
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
