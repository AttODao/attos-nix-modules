{ config, lib, ... }:
{
  config = lib.mkIf config.modules.zsh.enable {
    programs.zsh = {
      enable = true;
      autosuggestions.enable = true;
      syntaxHighlighting.enable = true;
    };

    programs.starship = {
      enable = true;

      settings = import ./settings.nix;
    };
  };
}
