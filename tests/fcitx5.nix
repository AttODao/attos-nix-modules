# nix-instantiate --eval --strict tests/fcitx5.nix \
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
  cfg = t.hmFor [ { modules.fcitx5.enable = true; } ];
  relocated = t.hmFor [
    { modules.fcitx5.enable = true; }
    { home-manager.users.test.xdg.configHome = "/home/test/config"; }
  ];
  invalid = builtins.tryEval (t.cfgFor [ { modules.fcitx5.enable = "yes"; } ]).modules.fcitx5.enable;
in
assert !base.modules.fcitx5.enable;
assert cfg.i18n.inputMethod.enable && cfg.i18n.inputMethod.type == "fcitx5";
assert cfg.i18n.inputMethod.fcitx5.waylandFrontend;
assert lib.all (p: lib.elem p cfg.i18n.inputMethod.fcitx5.addons) (
  with pkgs;
  [
    fcitx5-gtk
    fcitx5-skk
    qt6Packages.fcitx5-configtool
  ]
);
assert cfg.i18n.inputMethod.fcitx5.settings.globalOptions."Hotkey/AltTriggerKeys"."0" == "";
assert cfg.i18n.inputMethod.fcitx5.settings.inputMethod."Groups/0"."DefaultIM" == "skk";
assert cfg.i18n.inputMethod.fcitx5.settings.inputMethod."Groups/0/Items/1"."Layout" == "";
assert !cfg.xdg.configFile.fcitx5.enable;
assert cfg.home.activation ? installFcitx5Config;
assert lib.hasInfix "install -m 600" cfg.home.activation.installFcitx5Config.data;
assert lib.hasInfix "/home/test/config/fcitx5" relocated.home.activation.installFcitx5Config.data;
assert cfg.systemd.user.services.fcitx5-daemon.Service.ExitType == "cgroup";
assert lib.hasInfix "Hidden=true" cfg.xdg.configFile."autostart/org.fcitx.Fcitx5.desktop".text;
assert lib.hasSuffix ".drv" cfg.home.activationPackage.drvPath;
assert !invalid.success;
true
