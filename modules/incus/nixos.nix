{
  config,
  lib,
  pkgs,
  utils,
  attopkgs,
  ...
}:
let
  cfg = config.modules.incus;
  native = config.virtualisation.incus;
  vm = lib.getExe attopkgs.vm;
  definition = name: vm: {
    inherit (vm)
      launchConfig
      managedDeviceNames
      credentialFiles
      credentialRestartUnits
      ;
    credentialUnit = if vm.credentialFiles == { } then null else "incus-vm-credentials-${name}.service";
  };
  vmConfig = pkgs.writeText "vm.json" (
    builtins.toJSON {
      inherit (cfg.rebuild) flakeFile;
      virtualMachines = lib.mapAttrs definition cfg.virtualMachines;
    }
  );
  # Per-VM, so a delivery unit only restarts when its own credentials change.
  credentialConfig =
    name: vm:
    pkgs.writeText "vm-credentials-${name}.json" (
      builtins.toJSON { virtualMachines.${name} = definition name vm; }
    );
  vmCli =
    pkgs.runCommand "vm"
      {
        nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
        meta.mainProgram = "vm";
      }
      ''
        makeWrapper ${vm} $out/bin/vm \
          --add-flags ${lib.escapeShellArg "--config ${vmConfig}"} \
          --prefix PATH : ${
            lib.makeBinPath [
              native.clientPackage
              config.nix.package
            ]
          }
      '';
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
        environment.systemPackages = lib.optional (cfg.virtualMachines != { }) vmCli;
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
          path = [ native.clientPackage ];
          serviceConfig = {
            ExecCondition = [
              (utils.escapeSystemdExecArgs [
                vm
                "preseed-condition"
                initializePool
              ])
            ];
            ExecStartPre = map (
              module: "${pkgs.kmod}/bin/modprobe ${lib.escapeShellArg module}"
            ) cfg.preseedKernelModules;
          };
        };
      })
      {
        systemd.services = lib.mapAttrs' (
          name: vm':
          lib.nameValuePair "incus-vm-credentials-${name}" {
            description = "Deliver runtime credentials to Incus VM ${name}";
            wantedBy = [ "multi-user.target" ];
            requires = [ "incus.service" ];
            after = [
              "incus.service"
              "incus-startup.service"
            ];
            path = [ native.clientPackage ];
            unitConfig.RequiresMountsFor = builtins.attrValues vm'.credentialFiles;
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              Restart = "on-failure";
              RestartSec = "5s";
              UMask = "0077";
              # Absent/Stopped VMs are skipped; Running ones retry until the agent answers.
              ExecStart = utils.escapeSystemdExecArgs [
                vm
                "--config"
                (credentialConfig name vm')
                name
                "deliver-credentials"
              ];
            };
          }
        ) credentialVMs;
      }
    ]
  );
}
