{
  osConfig,
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
      # Suggestions move from Ctrl+Space to Ctrl+Alt+Space; the `when` clauses leave VS Code's own
      # Ctrl+Alt+Space binding (suggestion focus toggle) active while the widget is visible.
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
