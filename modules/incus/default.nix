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
    enable = lib.mkEnableOption "shared Incus host and guest CLI";
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
    rebuild.flake = lib.mkOption {
      type = lib.types.nullOr (lib.types.strMatching "[^#[:space:]]+");
      default = null;
      example = "server-nix";
      description = "Flake reference without an attribute (a registry alias, git+https URL or path:) whose nixosConfigurations of the same names the guest CLI builds creation images and guest systems from; required when guests are declared. The latest revision is fetched on every build; `guest NAME rebuild ACTION FLAKE` or `--flake` overrides it.";
    };

    guests = lib.mkOption {
      default = { };
      description = ''
        Incus KVM VMs and system containers managed only by the guest CLI; host
        activation never builds images, creates, starts or stops them.
        guest <name> boot builds a missing guest from system.build.metadata plus
        qemuImage (VM) or squashfs (container) of rebuild.flake, launches it
        and deletes the creation image. Without boot.autostart Incus restores the
        last running state at host boot. A same-name instance of the other type is
        an error, never converted or deleted. Removed entries are not deleted.
      '';
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            type = lib.mkOption {
              type = lib.types.enum [
                "virtual-machine"
                "container"
              ];
              description = "Incus instance type. The flake configuration must match: containers set boot.isContainer, VMs enable the Incus agent.";
            };
            launchConfig = lib.mkOption {
              type = lib.types.attrsOf json.type;
              description = ''
                Native Incus launch stdin configuration, including any profiles,
                config and devices. No privilege, disk or network defaults are added.
                This is used only when guest boot creates a missing instance.
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
              description = "Guest absolute destination paths mapped to host runtime credential paths. Destination parents must be dedicated credential directories: missing ones are created root:root 0700; existing ones must already be root:root 0700 and are never chmod/chowned. Shared top-level/system parents and dot path segments are rejected. Each file is delivered to this guest only as root:root 0600 via local/default Incus, then atomically renamed. No contents or host Age identity are copied into images/store. Consumer owns secret supply and rotation.";
            };
            credentialRestartUnits = lib.mkOption {
              type = lib.types.listOf (lib.types.strMatching "[^[:space:]/]+\\.service");
              default = [ ];
              description = "Guest service units restarted after all credentialFiles are delivered. Rotation must restart incus-guest-credentials-<name>.service on the host.";
            };
            managedDeviceNames = lib.mkOption {
              type = lib.types.listOf lib.types.nonEmptyStr;
              default = [ ];
              description = ''
                Opt-in devices from launchConfig.devices to upsert on every guest boot
                and applying guest rebuild.
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
