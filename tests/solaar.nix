# nix-instantiate --eval --strict tests/solaar.nix \
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
  enabledCfg = t.cfgFor [
    {
      modules.solaar.enable = true;
      modules.noctalia.enable = true;
      modules.hyprland.enable = true;
    }
  ];
  enabled = t.hm enabledCfg "test";
  selectedCfg = t.cfgFor [
    {
      modules.solaar.enable = true;
      programs.solaar.package = pkgs.solaar.overrideAttrs { pname = "solaar-selected"; };
      home-manager.users.test.xdg.configFile = {
        "solaar/rules.yaml".source = ./solaar.nix;
        "solaar/config.yaml".source = ./solaar.nix;
      };
    }
  ];
  selected = t.hm selectedCfg "test";
  customRules = t.hmFor [
    {
      modules.solaar.enable = true;
      home-manager.users.test.xdg.configFile."solaar/rules.yaml".text = "# custom rules";
    }
  ];
  invalidType =
    builtins.tryEval
      (t.cfgFor [ { modules.solaar.enable = "yes"; } ]).modules.solaar.enable;
  rules = enabled.xdg.configFile."solaar/rules.yaml".text;
in
assert !base.modules.solaar.enable;
assert !base.programs.solaar.enable;
assert builtins.elem pkgs.solaar enabled.home.packages;
assert builtins.elem pkgs.kando enabled.home.packages;
assert lib.elem selectedCfg.programs.solaar.package selected.home.packages;
assert selectedCfg.programs.solaar.package.pname == "solaar-selected";
assert
  selected.systemd.user.services.solaar.Service.ExecStart == [
    "${selectedCfg.programs.solaar.package}/bin/solaar -w hide"
  ];
assert selected.xdg.configFile."solaar/rules.yaml".source == ./solaar.nix;
assert selected.xdg.configFile."solaar/config.yaml".source == ./solaar.nix;
assert customRules.xdg.configFile."solaar/rules.yaml".text == "# custom rules";
assert
  enabled.systemd.user.services.solaar.Service.ExecStart == [ "${pkgs.solaar}/bin/solaar -w hide" ];
assert enabled.systemd.user.services.kando.Service.ExecStart == [ "${pkgs.kando}/bin/kando" ];
assert enabled.systemd.user.services.solaar.Install.WantedBy == [ "graphical-session.target" ];
assert enabled.systemd.user.services.kando.Install.WantedBy == [ "graphical-session.target" ];
assert
  builtins.readFile enabled.xdg.configFile."solaar/config.yaml".source
  == builtins.readFile ../modules/solaar/config.yaml;
assert lib.hasInfix
  (builtins.unsafeDiscardStringContext "${enabled.programs.noctalia.package}/bin/noctalia")
  rules;
assert lib.hasInfix (builtins.unsafeDiscardStringContext "${pkgs.kando}/bin/kando") rules;
assert lib.hasInfix "\"--menu\"\n  - \"default\"" rules;
assert lib.hasInfix ''"--close-menu"'' rules;
assert lib.hasInfix "MouseClick: [left, click]" rules;
assert !(lib.hasInfix "@OPEN_" rules) && !(lib.hasInfix "@CLOSE_" rules);
assert
  (builtins.head enabled.wayland.windowManager.hyprland.settings.window_rule).size == "100% 100%";
assert enabledCfg.modules.noctalia.enable;
assert lib.hasSuffix ".drv" enabled.home.activationPackage.drvPath;
assert !invalidType.success;
assert enabledCfg.programs.solaar.enable;
assert enabledCfg.hardware.logitech.wireless.enable;
assert !enabledCfg.programs.solaar.userService.enable;
true
