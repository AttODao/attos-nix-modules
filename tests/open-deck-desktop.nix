# nix-instantiate --eval --strict tests/open-deck-desktop.nix \
#   --arg nixpkgs /path/to/nixpkgs --arg homeManager /path/to/home-manager
{
  nixpkgs,
  homeManager,
  system ? builtins.currentSystem,
}:
let
  t = import ./lib.nix { inherit nixpkgs homeManager system; };
  inherit (t) lib;
  disabled = t.cfgFor [ ];
  enabledCfg = t.cfgFor [ { modules.open-deck-desktop.enable = true; } ];
  enabled = t.hm enabledCfg "test";
  package = lib.findFirst (p: lib.getName p == "open-deck-desktop") null enabled.home.packages;
  invalidType =
    builtins.tryEval
      (t.cfgFor [ { modules.open-deck-desktop.enable = "yes"; } ]).modules.open-deck-desktop.enable;
in
assert !disabled.modules.open-deck-desktop.enable;
assert enabledCfg.programs.appimage.enable;
assert enabledCfg.programs.appimage.binfmt == false;
assert enabled.home.activationPackage.drvPath != "";
assert package.pname == "open-deck-desktop" && package.version == "1.0.6";
assert package.src.outputHash == "sha256-khOQQ9HJYxveg6LO+AwLKUwkghSj3jelNtLNZUoH+iY=";
assert !(enabled.home.activation ? updateOpenDeckDesktop);
assert !invalidType.success;
true
