# nix-instantiate --eval --strict tests/vscode.nix \
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
  enabled = t.hmFor [ { modules.vscode.enable = true; } ];
  bindings = enabled.programs.vscode.profiles.default.keybindings;
  invalid = builtins.tryEval (t.cfgFor [ { modules.vscode.enable = "yes"; } ]).modules.vscode.enable;
in
assert !base.modules.vscode.enable;
assert !base.home-manager.users.test.programs.vscode.enable;
assert enabled.programs.vscode.enable;
assert builtins.elem enabled.programs.vscode.package enabled.home.packages;
assert
  map (binding: binding.key) bindings == [
    "ctrl+j"
    "ctrl+alt+j"
    "ctrl+q"
    "ctrl+space"
    "ctrl+space"
    "ctrl+space"
    "ctrl+space"
    "ctrl+space"
    "ctrl+space"
    "ctrl+alt+space"
    "ctrl+alt+space"
  ];
assert
  map (binding: binding.command) bindings == [
    "-workbench.action.togglePanel"
    "workbench.action.togglePanel"
    "-workbench.action.quit"
    "-editor.action.triggerSuggest"
    "-focusSuggestion"
    "-toggleSuggestionDetails"
    "-workbench.action.terminal.triggerSuggest"
    "-workbench.action.terminal.suggestToggleDetails"
    "-workbench.action.terminal.sendSequence"
    "editor.action.triggerSuggest"
    "workbench.action.terminal.triggerSuggest"
  ];
assert
  (builtins.elemAt bindings 9).when
  == "textInputFocus && !editorReadonly && editorHasCompletionItemProvider && !suggestWidgetVisible";
assert
  (builtins.elemAt bindings 10).when
  == "terminalFocus && !terminalSuggestWidgetVisible && config.terminal.integrated.suggest.enabled";
assert lib.hasSuffix ".drv" enabled.home.activationPackage.drvPath;
assert !invalid.success;
true
