{ config, lib, ... }:
{
  config = lib.mkIf config.modules.zsh.enable {
    programs.zsh = {
      enable = true;
      autosuggestions.enable = lib.mkDefault true;
      syntaxHighlighting.enable = lib.mkDefault true;
    };

    programs.starship = {
      enable = true;
      # Every leaf is a default, so a consumer can override part of the prompt without mkForce.
      settings = lib.mapAttrsRecursive (_: lib.mkDefault) (import ./settings.nix { inherit lib; });
    };
  };
}
