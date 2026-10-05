# nix-instantiate --eval --strict tests/pandora-launcher.nix \
#   --arg nixpkgs /path/to/nixpkgs --arg homeManager /path/to/home-manager
{
  nixpkgs,
  homeManager,
  system ? builtins.currentSystem,
}:
let
  t = import ./lib.nix { inherit nixpkgs homeManager system; };
  inherit (t) pkgs lib;
  base = t.cfgFor [ ];
  enabled = t.hmFor [ { modules.pandora-launcher.enable = true; } ];
  invalidType =
    builtins.tryEval
      (t.cfgFor [ { modules.pandora-launcher.enable = "yes"; } ]).modules.pandora-launcher.enable;
in
assert !base.modules.pandora-launcher.enable;
assert builtins.elem t.attopkgs.pandora-launcher enabled.home.packages;
assert builtins.elem t.attopkgs.pandoragh enabled.home.packages;
assert lib.hasSuffix ".drv" enabled.home.activationPackage.drvPath;
assert lib.hasInfix "--set LC_ALL en_US.UTF-8 --set LANG en_US.UTF-8" (
  builtins.concatStringsSep " " t.attopkgs.pandora-launcher.makeWrapperArgs
);
assert !invalidType.success;
true
