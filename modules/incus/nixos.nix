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
  ps = import ../public-services/lib.nix { inherit lib; };
  manifest = pkgs.writeText "incus-virtual-machines.json" (
    builtins.toJSON {
      virtualMachines = lib.mapAttrs (name: instance: {
        alias = "server-dotfiles-${name}";
        inherit (instance) launchConfig managedDeviceNames;
        metadata = toString instance.metadata;
        disk = toString instance.disk;
      }) cfg.virtualMachines;
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
        environment.systemPackages = lib.optional (cfg.rebuild.flakeFile != null) (
          attopkgs.vm-rebuild {
            flakeFile = cfg.rebuild.flakeFile;
            virtualMachines = builtins.attrNames cfg.virtualMachines;
            incus = native.clientPackage;
          }
        );
        assertions = [
          {
            assertion = lib.all (vm: vm.credentialRestartUnits == [ ] || vm.credentialFiles != { }) (
              builtins.attrValues cfg.virtualMachines
            );
            message = "modules.incus: credentialRestartUnits require credentialFiles on the same VM.";
          }
          {
            assertion =
              cfg.rebuild.flakeFile == null
              || (lib.hasSuffix "/flake.nix" cfg.rebuild.flakeFile && cfg.virtualMachines != { });
            message = "modules.incus.rebuild.flakeFile must name flake.nix and requires declared virtualMachines.";
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
            requires = [ "incus-virtual-machines.service" ];
            after = [ "incus-virtual-machines.service" ];
            path = [ native.clientPackage ];
            unitConfig.RequiresMountsFor = builtins.attrValues vm.credentialFiles;
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              Restart = "on-failure";
              RestartSec = "5s";
              UMask = "0077";
            };
            script =
              "set -eu\n"
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
      (lib.mkIf (cfg.virtualMachines != { }) {
        systemd.services.incus-virtual-machines = {
          description = "Import explicit Incus qcow2 images and create missing KVM virtual machines";
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
            ExecStartPre = map (
              module: "${pkgs.kmod}/bin/modprobe ${lib.escapeShellArg module}"
            ) cfg.provisionKernelModules;
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
