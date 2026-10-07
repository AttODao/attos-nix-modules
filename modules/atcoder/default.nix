{ config, lib, ... }:
{
  imports = [ ../zsh ];

  options.modules.atcoder.enable = lib.mkEnableOption "shared AtCoder Go tools and commands";

  config = lib.mkIf config.modules.atcoder.enable {
    modules.zsh.enable = true;
    home-manager.sharedModules = [ ./home.nix ];
  };
}
