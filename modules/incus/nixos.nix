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
  guest = lib.getExe attopkgs.guest;
  definition = name: guest: {
    inherit (guest)
      type
      launchConfig
      managedDeviceNames
      credentialFiles
      credentialRestartUnits
      ;
    credentialUnit =
      if guest.credentialFiles == { } then null else "incus-guest-credentials-${name}.service";
  };
  guestConfig = pkgs.writeText "guest.json" (
    builtins.toJSON {
      inherit (cfg.rebuild) flakeFile;
      guests = lib.mapAttrs definition cfg.guests;
    }
  );
  # Per-guest, so a delivery unit only restarts when its own credentials change.
  credentialConfig =
    name: guest:
    pkgs.writeText "guest-credentials-${name}.json" (
      builtins.toJSON { guests.${name} = definition name guest; }
    );
  guestCli =
    pkgs.runCommand "guest"
      {
        nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
        meta.mainProgram = "guest";
      }
      ''
        makeWrapper ${guest} $out/bin/guest \
          --add-flags ${lib.escapeShellArg "--config ${guestConfig}"} \
          --prefix PATH : ${
            lib.makeBinPath [
              native.clientPackage
              config.nix.package
            ]
          }
      '';
  credentialGuests = lib.filterAttrs (_: guest: guest.credentialFiles != { }) cfg.guests;
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
        environment.systemPackages = lib.optional (cfg.guests != { }) guestCli;
        assertions = [
          {
            assertion = lib.all (guest: guest.credentialRestartUnits == [ ] || guest.credentialFiles != { }) (
              builtins.attrValues cfg.guests
            );
            message = "modules.incus: credentialRestartUnits require credentialFiles on the same guest.";
          }
          {
            assertion =
              if cfg.rebuild.flakeFile == null then
                cfg.guests == { }
              else
                lib.hasSuffix "/flake.nix" cfg.rebuild.flakeFile && cfg.guests != { };
            message = "modules.incus.rebuild.flakeFile must name flake.nix and is required exactly when guests are declared.";
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
                guest
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
          name: guest':
          lib.nameValuePair "incus-guest-credentials-${name}" {
            description = "Deliver runtime credentials to Incus guest ${name}";
            wantedBy = [ "multi-user.target" ];
            requires = [ "incus.service" ];
            after = [
              "incus.service"
              "incus-startup.service"
            ];
            path = [ native.clientPackage ];
            unitConfig.RequiresMountsFor = builtins.attrValues guest'.credentialFiles;
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              Restart = "on-failure";
              RestartSec = "5s";
              UMask = "0077";
              # Absent/Stopped guests are skipped; Running ones retry until incus exec answers.
              ExecStart = utils.escapeSystemdExecArgs [
                guest
                "--config"
                (credentialConfig name guest')
                name
                "deliver-credentials"
              ];
            };
          }
        ) credentialGuests;
      }
    ]
  );
}
