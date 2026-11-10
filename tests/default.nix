# Evaluation-only tests of the shared modules (flake checks; `nix flake check --no-build`).
#
# - modules-disabled: a minimal NixOS system with nixosModules.default and nothing enabled must not
#   differ from the same system without the shared modules (packages, units, /etc, users, firewall,
#   enabled services/programs). Intentional differences go into `allowed` below.
# - module-<name>: the minimal system with only that feature enabled evaluates to a toplevel
#   drvPath. The list comes from the directories in modules/, so new modules are tested
#   automatically; required options get values from ./fixtures.nix.
# - home-manager-<name>: a standalone Home Manager configuration with homeManager.<name>
#   (flake.modules.homeManager), for every feature with a home.nix that works without NixOS.
# - home-manager-unknown-option: a misspelt modules.* setting fails the standalone evaluation.
# Skipped features are listed with the reason (`skip`, `hmSkip`).
{
  lib,
  nixpkgs,
  home-manager,
  system,
  nixosModule,
  homeModules,
}:
let
  fixtures = import ./fixtures.nix { inherit lib hostName; };
  hostName = "attos-test";
  pkgs = import nixpkgs {
    inherit system;
    config.allowUnfree = true;
  };

  base = {
    nixpkgs.hostPlatform = system;
    nixpkgs.config.allowUnfree = true;
    fileSystems."/" = {
      device = "/dev/disk/by-label/nixos";
      fsType = "ext4";
    };
    boot.loader.grub.enable = false;
    networking.hostName = hostName;
    system.stateVersion = "26.05";
    # The manuals evaluate every option's documentation; that only costs memory here.
    documentation.enable = false;
  };
  nixos = modules: nixpkgs.lib.nixosSystem { modules = [ base ] ++ modules; };

  dirs = map baseNameOf (import ../modules).imports;
  shared = nixos [ nixosModule ];

  # Public services: `modules.<name>` is the standalone submodule from ps.moduleOptions, and the
  # check enables the public registry record (modules.public-services.<FQDN>.<name>) instead.
  publicServices = lib.filter (
    name: shared.options.modules ? ${name} && lib.isOption shared.options.modules.${name}
  ) dirs;

  # Directories without a module-<name> check, with the reason.
  skip = {
    home-manager = "no enable option; every check with a Home Manager user uses it";
    public-services = "the registry itself; each service check fills it";
  };

  enable =
    name:
    if lib.elem name publicServices then
      {
        modules.public-services."${name}.${hostName}.example".${name} = {
          enable = true;
          host = hostName;
        }
        // fixtures.services.${name} or { };
      }
    else
      { modules.${name}.enable = true; };

  hmUser = {
    users.users.tester.isNormalUser = true;
    modules.home-manager.users = [ "tester" ];
    home-manager.sharedModules = [ { manual.manpages.enable = false; } ];
  };

  moduleChecks = lib.listToAttrs (
    map (name: {
      name = "module-${name}";
      value =
        (nixos [
          nixosModule
          hmUser
          (enable name)
          (fixtures.modules.${name} or { })
        ]).config.system.build.toplevel;
    }) (lib.filter (name: !skip ? ${name}) dirs)
  );

  # Features whose home.nix cannot run without NixOS, with the reason.
  hmSkip = {
    hyprland = "home.nix reads osConfig.programs.hyprland.{package,portalPackage} (NixOS programs.hyprland)";
    attos-mouse = "home.nix reads osConfig.programs.uwsm.package (NixOS programs.uwsm)";
  };

  # Same evaluation as home-manager.lib.homeManagerConfiguration.
  homeManager =
    modules:
    import "${home-manager}/lib/eval-config.nix" {
      inherit pkgs;
      modules = modules ++ [
        {
          home = {
            username = "tester";
            homeDirectory = "/home/tester";
            stateVersion = "26.05";
          };
          manual.manpages.enable = false;
        }
      ];
    };

  homeChecks = lib.mapAttrs' (name: module: {
    name = "home-manager-${name}";
    value =
      (homeManager [
        module
        (fixtures.home.${name} or { })
      ]).activationPackage;
  }) (lib.filterAttrs (name: _: name != "default" && !hmSkip ? ${name}) homeModules);

  # A misspelt setting must fail instead of disappearing into the standalone NixOS-side evaluation
  # (home-manager-foot is the same configuration without the typo).
  homeUnknownOption =
    let
      result =
        builtins.tryEval
          (homeManager [
            homeModules.foot
            { modules.foot.enabel = true; }
          ]).activationPackage.drvPath;
    in
    if result.success then
      throw "home-manager-unknown-option: a misspelt modules.* setting was accepted"
    else
      pkgs.writeText "home-manager-unknown-option" "rejected\n";

  # --- modules-disabled ---------------------------------------------------------------------
  summary =
    { config, options, ... }:
    let
      names = attrs: lib.attrNames attrs;
      # Read `enable` through the declared options and skip renamed/removed aliases (invisible
      # options): their config values warn, throw or abort when read.
      enabled =
        opts:
        lib.attrNames (
          lib.filterAttrs (
            _: o:
            let
              e = o.enable or null;
              r = builtins.tryEval (
                lib.isOption e && (e.visible or true) != false && e.isDefined && e.value == true
              );
            in
            builtins.isAttrs o && !lib.isOption o && r.success && r.value
          ) opts
        );
      fw = config.networking.firewall;
    in
    {
      systemPackages = lib.sort lib.lessThan (map lib.getName config.environment.systemPackages);
      systemdServices = names config.systemd.services;
      systemdSockets = names config.systemd.sockets;
      systemdTimers = names config.systemd.timers;
      userServices = names config.systemd.user.services;
      etc = names config.environment.etc;
      users = names config.users.users;
      groups = names config.users.groups;
      tcpPorts = map toString fw.allowedTCPPorts;
      udpPorts = map toString fw.allowedUDPPorts;
      tcpPortRanges = map builtins.toJSON fw.allowedTCPPortRanges;
      udpPortRanges = map builtins.toJSON fw.allowedUDPPortRanges;
      firewallInterfaces = names fw.interfaces;
      services = enabled options.services;
      programs = enabled options.programs;
    };

  # Differences that importing nixosModules.default causes on purpose, per summary key.
  allowed = { };

  disabledCheck =
    let
      plain = summary (nixos [ ]);
      withShared = summary shared;
      diff = lib.filterAttrs (_: d: d.added != [ ] || d.removed != [ ]) (
        lib.mapAttrs (
          key: values:
          let
            allow = allowed.${key} or [ ];
          in
          {
            added = lib.subtractLists (plain.${key} ++ allow) values;
            removed = lib.subtractLists (values ++ allow) plain.${key};
          }
        ) withShared
      );
    in
    if diff != { } then
      throw "modules-disabled: importing nixosModules.default with nothing enabled changed the system: ${builtins.toJSON diff}"
    else
      pkgs.writeText "modules-disabled" (builtins.toJSON withShared);
in
{
  modules-disabled = disabledCheck;
  home-manager-unknown-option = homeUnknownOption;
}
// moduleChecks
// homeChecks
