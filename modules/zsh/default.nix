{ config, lib, ... }:
{
  imports = [ ./nixos.nix ];

  options.modules.zsh.enable = lib.mkEnableOption "shared Zsh configuration with Starship";

  config = lib.mkIf config.modules.zsh.enable {
    home-manager.sharedModules = [ ./home.nix ];
  };
}
