# nix-instantiate --eval --strict tests/zsh.nix \
#   --arg nixpkgs /path/to/nixpkgs --arg homeManager /path/to/home-manager
{
  nixpkgs,
  homeManager,
  system ? builtins.currentSystem,
}:
let
  t = import ./lib.nix { inherit nixpkgs homeManager system; };
  inherit (t) lib;
  base = t.cfgFor [ ];
  enabledCfg = t.cfgFor [ { modules.zsh.enable = true; } ];
  enabled = t.hm enabledCfg "test";
  invalid = builtins.tryEval (t.cfgFor [ { modules.zsh.enable = "yes"; } ]).modules.zsh.enable;
in
assert !base.modules.zsh.enable;
assert
  !base.home-manager.users.test.programs.zsh.enable
  && !base.home-manager.users.test.programs.starship.enable;
assert !base.programs.zsh.enable && !base.programs.starship.enable;
assert enabled.programs.zsh.enable && enabled.programs.zsh.autosuggestion.enable;
assert enabled.programs.zsh.syntaxHighlighting.enable;
assert enabledCfg.programs.zsh.enable && enabledCfg.programs.zsh.autosuggestions.enable;
assert enabledCfg.programs.zsh.syntaxHighlighting.enable;
assert enabled.programs.starship.enable && enabled.programs.starship.enableZshIntegration;
assert enabledCfg.programs.starship.enable && enabledCfg.programs.starship.enableZshIntegration;
assert enabled.programs.starship.settings == enabledCfg.programs.starship.settings;
assert enabled.programs.starship.settings.palette == "gruvbox_dark";
assert enabled.programs.starship.settings.palettes.gruvbox_dark.color_orange == "#d65d0e";
assert enabled.programs.starship.settings.time.time_format == "%R";
assert lib.hasInfix "starship init zsh" enabled.programs.zsh.initContent;
assert lib.hasInfix "starship init zsh" enabledCfg.programs.zsh.promptInit;
assert enabledCfg.users.defaultUserShell == base.users.defaultUserShell;
assert lib.hasSuffix ".drv" enabled.home.activationPackage.drvPath;
assert !invalid.success;
true
