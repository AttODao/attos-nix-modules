{
  nixpkgs,
  homeManager,
  system ? builtins.currentSystem,
}:
let
  t = import ./lib.nix { inherit nixpkgs homeManager system; };
  inherit (t) lib;
  input = {
    modules.incus = {
      rebuild.flakeFile = "/srv/server-dotfiles/flake.nix";
      stateDir = "/srv/incus-state";
      containers.desktop = {
        metadata = ./lib.nix;
        rootfs = ./lib.nix;
        launchConfig = { };
      };
    };
  };
  disabled = t.cfgFor [ input ];
  enabled = t.cfgFor [
    input
    { modules.incus.enable = true; }
  ];
  noRebuild = t.cfgFor [ { modules.incus.enable = true; } ];
  installed = c: lib.filter (p: (p.name or "") == "container-rebuild") c.environment.systemPackages;
  invalid = t.cfgFor [
    input
    {
      modules.incus.enable = true;
      modules.incus.rebuild.flakeFile = lib.mkForce "/srv/server-dotfiles/not-a-flake.nix";
    }
  ];
in
assert installed disabled == [ ];
assert installed noRebuild == [ ];
assert builtins.length (installed enabled) == 1;
assert lib.all (a: a.assertion) enabled.assertions;
assert lib.any (a: !a.assertion && lib.hasInfix "rebuild.flakeFile" a.message) invalid.assertions;
assert noRebuild.modules.incus.rebuild.flakeFile == null;
assert enabled.users.users.test.extraGroups == [ ];
true
