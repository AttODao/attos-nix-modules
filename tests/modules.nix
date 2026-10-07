# nix-instantiate --eval --strict tests/modules.nix \
#   --arg nixpkgs /path/to/nixpkgs --arg homeManager /path/to/home-manager
{
  nixpkgs,
  homeManager,
  system ? builtins.currentSystem,
}:
let
  t = import ./lib.nix { inherit nixpkgs homeManager system; };
  inherit (t) pkgs lib;
  expectedPackages = with pkgs; [
    nerd-fonts.inconsolata
    noto-fonts-cjk-sans
    noto-fonts-cjk-serif
  ];
  base = t.cfgFor [ ];
  backups = t.cfgFor [ { modules.home-manager.backupFileExtension = "backup"; } ];
  nativeBackups = t.cfgFor [
    {
      modules.home-manager.backupFileExtension = "backup";
      home-manager.backupFileExtension = "previous";
    }
  ];
  footCfg = t.cfgFor [ { modules.foot.enable = true; } ];
  foot = t.hm footCfg "test";
  fontsCfg = t.cfgFor [ { modules.fonts.enable = true; } ];
  fonts = t.hm fontsCfg "test";
  overridden = t.hmFor [
    { modules.foot.enable = true; }
    {
      home-manager.users.test = {
        programs.foot.settings.main.font = "monospace:size=13";
        programs.foot.settings.colors-dark.alpha = 1.0;
        fonts.fontconfig.defaultFonts.monospace = [ "monospace" ];
      };
    }
  ];
  invalidType = builtins.tryEval (t.cfgFor [ { modules.foot.enable = "yes"; } ]).modules.foot.enable;
  oldHomeOption =
    builtins.tryEval
      (t.cfgFor [ { home-manager.users.test.modules.foot.enable = true; } ])
      .home-manager.users.test.modules.foot.enable;
  missingDependency =
    builtins.tryEval
      (t.cfgFor [
        {
          modules.foot.enable = true;
          modules.fonts.enable = false;
        }
      ]).modules.fonts.enable;
in
assert base.home-manager.backupFileExtension == null;
assert backups.home-manager.backupFileExtension == "backup";
assert nativeBackups.home-manager.backupFileExtension == "previous";
assert !base.modules.foot.enable && !base.modules.fonts.enable;
assert !base.home-manager.users.test.programs.foot.enable;
assert footCfg.modules.foot.enable && footCfg.modules.fonts.enable;
assert foot.fonts.fontconfig.enable;
assert foot.programs.foot.enable && foot.programs.foot.server.enable;
assert foot.programs.foot.settings.main.font == "Inconsolata Nerd Font Mono:size=11";
assert foot.programs.foot.settings.colors-dark.alpha == 0.65;
assert lib.all (p: lib.elem p foot.home.packages) expectedPackages;
assert foot.fonts.fontconfig.defaultFonts.monospace == [ "Inconsolata Nerd Font Mono" ];
assert foot.xdg.configFile."foot/foot.ini".enable;
assert
  foot.systemd.user.services.foot.Service.ExecStart
  == [ "${foot.programs.foot.package}/bin/foot --server" ];
assert fontsCfg.modules.fonts.enable;
assert !fonts.programs.foot.enable && fonts.fonts.fontconfig.enable;
assert lib.all (p: lib.elem p fonts.home.packages) expectedPackages;
assert lib.all (p: lib.elem p fontsCfg.fonts.packages) expectedPackages;
assert fontsCfg.fonts.fontconfig.defaultFonts.monospace == [ "Inconsolata Nerd Font Mono" ];
assert overridden.programs.foot.settings.main.font == "monospace:size=13";
assert overridden.programs.foot.settings.colors-dark.alpha == 1.0;
assert overridden.fonts.fontconfig.defaultFonts.monospace == [ "monospace" ];
assert !invalidType.success && !oldHomeOption.success && !missingDependency.success;
true
