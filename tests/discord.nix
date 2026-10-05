# nix-instantiate --eval --strict tests/discord.nix \
#   --arg nixpkgs /path/to/nixpkgs --arg homeManager /path/to/home-manager
{
  nixpkgs,
  homeManager,
  system ? builtins.currentSystem,
}:
let
  t = import ./lib.nix {
    inherit nixpkgs homeManager system;
    nixpkgsConfig.allowUnfree = true;
  };
  inherit (t) lib;
  base = t.cfgFor [ ];
  enabledCfg = t.cfgFor [ { modules.discord.enable = true; } ];
  enabled = t.hm enabledCfg "test";
  service = enabled.systemd.user.services.discord;
  invalid =
    builtins.tryEval
      (t.cfgFor [ { modules.discord.enable = "yes"; } ]).modules.discord.enable;
in
assert !base.modules.discord.enable;
assert !base.home-manager.users.test.programs.discord.enable;
assert enabled.programs.discord.enable;
assert enabledCfg.modules.fcitx5.enable;
assert enabled.i18n.inputMethod.enable && enabled.i18n.inputMethod.type == "fcitx5";
assert enabled.systemd.user.services ? fcitx5-daemon;
assert builtins.elem enabled.programs.discord.package enabled.home.packages;
assert service.Unit.Wants == [ "fcitx5-daemon.service" ];
assert
  service.Unit.After == [
    "graphical-session.target"
    "fcitx5-daemon.service"
  ];
assert
  service.Service.ExecStart
  == [ "${enabled.programs.discord.package}/bin/discord --start-minimized" ];
assert service.Service.Restart == "on-failure";
assert service.Service.RestartSec == 3;
assert service.Install.WantedBy == [ "graphical-session.target" ];
assert lib.hasSuffix ".drv" enabled.home.activationPackage.drvPath;
assert !invalid.success;
true
