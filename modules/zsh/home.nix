{
  osConfig,
  config,
  lib,
  ...
}:
{
  config = lib.mkIf osConfig.modules.zsh.enable {
    programs.zsh = {
      enable = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;
    };

    programs.starship = {
      enable = true;
      enableZshIntegration = true;

      settings = import ./settings.nix;
    };
  };
}
