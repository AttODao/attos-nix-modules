{
  osConfig,
  config,
  lib,
  ...
}:
{
  config = lib.mkIf osConfig.modules.vscode.enable {
    programs.vscode.enable = true;
    programs.vscode.profiles.default.keybindings = [
      {
        key = "ctrl+j";
        command = "-workbench.action.togglePanel";
      }
      {
        key = "ctrl+alt+j";
        command = "workbench.action.togglePanel";
      }
      {
        key = "ctrl+q";
        command = "-workbench.action.quit";
      }
      {
        key = "ctrl+space";
        command = "-editor.action.triggerSuggest";
      }
      {
        key = "ctrl+space";
        command = "-focusSuggestion";
      }
      {
        key = "ctrl+space";
        command = "-toggleSuggestionDetails";
      }
      {
        key = "ctrl+space";
        command = "-workbench.action.terminal.triggerSuggest";
      }
      {
        key = "ctrl+space";
        command = "-workbench.action.terminal.suggestToggleDetails";
      }
      {
        key = "ctrl+space";
        command = "-workbench.action.terminal.sendSequence";
      }
      # Keep the existing Ctrl+Alt+Space focus toggle while suggestions are visible.
      {
        key = "ctrl+alt+space";
        command = "editor.action.triggerSuggest";
        when = "textInputFocus && !editorReadonly && editorHasCompletionItemProvider && !suggestWidgetVisible";
      }
      {
        key = "ctrl+alt+space";
        command = "workbench.action.terminal.triggerSuggest";
        when = "terminalFocus && !terminalSuggestWidgetVisible && config.terminal.integrated.suggest.enabled";
      }
    ];
  };
}
