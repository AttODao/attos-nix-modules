{
  config,
  lib,
  pkgs,
  attopkgs,
  ...
}:
let
  cfg = config.modules.incus;
  native = config.virtualisation.incus;
  runner = pkgs.writeShellApplication {
    name = "attos-incus";
    runtimeInputs = [
      native.clientPackage
      pkgs.python3
    ];
    text = ''exec python3 ${./preseed.py} "$@"'';
  };
  credentialVMs = lib.filterAttrs (_: vm: vm.credentialFiles != { }) cfg.virtualMachines;
  preseed = native.preseed != null;
  pools = if !preseed then [ ] else native.preseed.storage_pools or [ ];
  singlePool =
    builtins.isList pools
    && builtins.length pools == 1
    && builtins.isAttrs (builtins.head pools)
    && lib.types.nonEmptyStr.check ((builtins.head pools).name or null);
  # Existing pools only skip bootstrap; they do not prove complete initialization.
  initializePool =
    if singlePool then
      (builtins.head pools).name
    else
      throw "modules.incus: supplied preseed.storage_pools must contain exactly one named storage pool; initialization is create-only.";
in
{
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        virtualisation.incus = {
          enable = true;
          package = lib.mkDefault cfg.package;
          preseed = lib.mkDefault cfg.preseed;
        };
        boot.initrd.kernelModules = cfg.initrdKernelModules;
        # QEMU/KVM and OVMF are supplied by the native Incus module, not libvirtd.
        boot.kernelModules = [ "kvm" ];
        networking.nftables.enable = lib.mkDefault true;
        environment.systemPackages = lib.optionals (cfg.virtualMachines != { }) [
          (attopkgs.vm {
            inherit (cfg.rebuild) flakeFile;
            virtualMachines = lib.mapAttrs (name: vm: {
              inherit (vm) launchConfig managedDeviceNames;
              credentialUnit = if vm.credentialFiles == { } then null else "incus-vm-credentials-${name}.service";
            }) cfg.virtualMachines;
            incus = native.clientPackage;
          })
          (attopkgs.vm-bootstrap {
            virtualMachines = builtins.attrNames cfg.virtualMachines;
            incus = native.clientPackage;
          })
        ];
        assertions = [
          {
            assertion = lib.all (vm: vm.credentialRestartUnits == [ ] || vm.credentialFiles != { }) (
              builtins.attrValues cfg.virtualMachines
            );
            message = "modules.incus: credentialRestartUnits require credentialFiles on the same VM.";
          }
          {
            assertion =
              if cfg.rebuild.flakeFile == null then
                cfg.virtualMachines == { }
              else
                lib.hasSuffix "/flake.nix" cfg.rebuild.flakeFile && cfg.virtualMachines != { };
            message = "modules.incus.rebuild.flakeFile must name flake.nix and is required exactly when virtualMachines are declared.";
          }
          {
            assertion = !preseed || singlePool;
            message = "modules.incus: supplied preseed.storage_pools must contain exactly one named storage pool; initialization is create-only.";
          }
        ];
      }
      (lib.mkIf preseed {
        systemd.services.incus-preseed = {
          restartIfChanged = false;
          serviceConfig = {
            ExecCondition = [
              "${runner}/bin/attos-incus condition ${lib.escapeShellArg initializePool}"
            ];
            ExecStartPre = map (
              module: "${pkgs.kmod}/bin/modprobe ${lib.escapeShellArg module}"
            ) cfg.preseedKernelModules;
          };
        };
      })
      {
        systemd.services = lib.mapAttrs' (
          name: vm:
          lib.nameValuePair "incus-vm-credentials-${name}" {
            description = "Deliver runtime credentials to Incus VM ${name}";
            wantedBy = [ "multi-user.target" ];
            requires = [ "incus.service" ];
            after = [
              "incus.service"
              "incus-startup.service"
            ];
            path = [
              native.clientPackage
              pkgs.gawk
            ];
            unitConfig.RequiresMountsFor = builtins.attrValues vm.credentialFiles;
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              Restart = "on-failure";
              RestartSec = "5s";
              UMask = "0077";
            };
            script = ''
              set -euo pipefail
              state=$(incus --force-local --project default list --format csv --columns ns \
                | awk -F, -v name=${lib.escapeShellArg name} '$1 == name { print $2 }')
              # Host activation never starts VMs; vm boot restarts this unit after starting one.
              case "$state" in ""|STOPPED) exit 0 ;; esac
            ''
            + lib.concatStrings (
              lib.mapAttrsToList (destination: source: ''
                incus --force-local --project default exec ${lib.escapeShellArg name} -- /bin/sh -eu -c ${lib.escapeShellArg ''
                  PATH=/run/current-system/sw/bin:/bin
                  [ ! -L "$1" ]
                  mkdir -p -m 0700 -- "$1"
                  [ "$(stat -c %u:%g:%a -- "$1")" = "0:0:700" ]
                ''} sh ${lib.escapeShellArg (builtins.dirOf destination)}
                incus --force-local --project default file push --uid 0 --gid 0 --mode 0600 \
                  ${lib.escapeShellArg source} ${lib.escapeShellArg "${name}${destination}.new"}
                incus --force-local --project default exec ${lib.escapeShellArg name} -- mv -fT -- \
                  ${lib.escapeShellArg "${destination}.new"} ${lib.escapeShellArg destination}
              '') vm.credentialFiles
            )
            + lib.optionalString (vm.credentialRestartUnits != [ ]) ''
              incus --force-local --project default exec ${lib.escapeShellArg name} -- systemctl restart ${lib.escapeShellArgs vm.credentialRestartUnits}
            '';
          }
        ) credentialVMs;
      }
    ]
  );
}
