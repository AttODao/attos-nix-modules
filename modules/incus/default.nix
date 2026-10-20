{
  lib,
  options,
  pkgs,
  ps,
  ...
}:
let
  json = pkgs.formats.json { };
  accountName = lib.types.strMatching "[a-z_][a-z0-9_-]*[$]?";
  # A plain source string keeps the root:root 0600 default; the submodule adds the guest owner.
  credentialFile = lib.types.coercedTo ps.absolutePath (source: { inherit source; }) (
    lib.types.submodule {
      options = {
        source = lib.mkOption {
          type = ps.absolutePath;
          description = "Host runtime path of the credential.";
        };
        owner = lib.mkOption {
          type = accountName;
          default = "root";
          description = "Guest user owning the delivered file and its dedicated parent directory.";
        };
        group = lib.mkOption {
          type = accountName;
          default = "root";
          description = "Guest group of the delivered file and its dedicated parent directory.";
        };
        mode = lib.mkOption {
          type = lib.types.strMatching "0[0-7]{3}";
          default = "0600";
          description = "Delivered file mode.";
        };
      };
    }
  );
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
              type = lib.types.addCheck (lib.types.attrsOf credentialFile) (
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
              example = lib.literalExpression ''
                {
                  "/var/lib/worker/token" = "/run/secrets/worker-token";
                  "/home/dev/.app/app.env" = {
                    source = "/run/secrets/app.env";
                    owner = "dev";
                    group = "users";
                  };
                }
              '';
              description = "Guest absolute destination paths mapped to host runtime credential paths, either a plain source path (delivered root:root 0600) or { source, owner, group, mode }. Destination parents must be dedicated credential directories owned by the file's owner and group with mode 0700: missing ones are created so; existing ones must already match and are never chmod/chowned. Shared top-level/system parents and dot path segments are rejected. Each file is delivered to this guest only via local/default Incus, then chowned/chmodded and atomically renamed. No contents or host Age identity are copied into images/store. Consumer owns secret supply and rotation.";
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
