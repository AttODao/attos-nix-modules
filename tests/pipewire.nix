# nix-instantiate --eval --strict tests/pipewire.nix \
#   --arg nixpkgs /path/to/nixpkgs --arg homeManager /path/to/home-manager
{
  nixpkgs,
  homeManager,
  system ? builtins.currentSystem,
}:
let
  t = import ./lib.nix { inherit nixpkgs homeManager system; };
  base = t.cfgFor [ ];
  enabled = t.cfgFor [ { modules.pipewire.enable = true; } ];
  invalidType =
    builtins.tryEval
      (t.cfgFor [ { modules.pipewire.enable = "yes"; } ]).modules.pipewire.enable;
in
assert !base.modules.pipewire.enable;
assert enabled.services.pipewire.enable;
assert enabled.services.pipewire.alsa.enable;
assert enabled.services.pipewire.pulse.enable;
assert enabled.security.rtkit.enable;
assert !invalidType.success;
true
