{
  osConfig,
  lib,
  ...
}:
{
  # Plugins and Starship come from the system zshrc; HM zsh keeps session
  # variables and other modules' shell integrations.
  config = lib.mkIf osConfig.modules.zsh.enable {
    programs.zsh.enable = true;
  };
}
