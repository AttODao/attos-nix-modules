# nix-instantiate --eval --strict tests/integrated.nix \
#   --arg nixpkgs /path/to/nixpkgs --arg homeManager /path/to/home-manager
{
  nixpkgs,
  homeManager,
  system ? builtins.currentSystem,
}:
let
  t = import ./lib.nix { inherit nixpkgs homeManager system; };
  inherit (t) lib exports;
  minimal = t.cfgFor [ ];
  empty = (t.evalSystem { users = [ ]; }).config;
  multi =
    (t.evalSystem {
      users = [
        "alice"
        "bob"
      ];
      modules = [ { modules.thunderbird.enable = true; } ];
    }).config;
  overridden = t.hmFor [
    { modules.foot.enable = true; }
    {
      home-manager.users.test = {
        home.stateVersion = "25.11";
        programs.foot.settings.main.font = "monospace:size=13";
      };
    }
  ];
  duplicateUsers = builtins.tryEval (
    (t.evalSystem {
      users = [
        "test"
        "test"
      ];
    }).config.system.build.toplevel.drvPath
  );
  missingUserCfg =
    (import "${toString nixpkgs}/nixos/lib/eval-config.nix" {
      inherit system;
      modules = [
        {
          system.stateVersion = "26.05";
          boot.isContainer = true;
          fileSystems."/" = {
            device = "none";
            fsType = "tmpfs";
          };
          modules.home-manager.users = [ "ghost" ];
        }
        exports.nixosModules.default
      ];
    }).config;
  missingUserAssert = builtins.any (
    a: !a.assertion && lib.hasInfix "modules.home-manager.users: 'ghost' must be declared" a.message
  ) missingUserCfg.assertions;
  commonArgs = t.cfgFor [
    {
      modules.pandora-launcher.enable = true;
      modules.pipeasio.enable = true;
    }
  ];
  commonHm = t.hm commonArgs "test";
  invalidType = builtins.tryEval (t.cfgFor [ { modules.foot.enable = "yes"; } ]).modules.foot.enable;
in
assert builtins.attrNames exports.nixosModules == [ "default" ];
assert builtins.attrNames exports.nixos == [ "default" ];
assert exports.nixos.default == exports.nixosModules.default;
assert !(exports ? home);
assert minimal.modules.home-manager.users == [ "test" ];
assert minimal.home-manager.useGlobalPkgs;
assert minimal.home-manager.useUserPackages;
assert minimal.home-manager.users.test.home.stateVersion == "26.05";
assert minimal.home-manager.users.test.programs.home-manager.enable;
assert !minimal.modules.foot.enable && !minimal.modules.thunderbird.enable;
assert empty.modules.home-manager.users == [ ];
assert empty.home-manager.users == { };
assert multi.services.gnome.evolution-data-server.enable;
assert multi.services.gnome.gnome-keyring.enable;
assert multi.home-manager.users.alice.programs.thunderbird.enable;
assert multi.home-manager.users.bob.programs.thunderbird.enable;
assert
  multi.home-manager.users.alice.programs.thunderbird.profiles.attodao.settings
  == multi.home-manager.users.bob.programs.thunderbird.profiles.attodao.settings;
assert builtins.elem t.attopkgs.pandora-launcher commonHm.home.packages;
assert builtins.elem t.attopkgs.pandoragh commonHm.home.packages;
assert builtins.elem t.attopkgs.pipeasio commonArgs.environment.systemPackages;
assert builtins.elem t.attopkgs.pipeasio commonHm.home.packages;
assert overridden.home.stateVersion == "25.11";
assert overridden.programs.foot.settings.main.font == "monospace:size=13";
assert !invalidType.success;
assert !duplicateUsers.success;
assert missingUserAssert;
true
