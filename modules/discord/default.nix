{ config, lib, ... }:
{
  imports = [ ../fcitx5 ];

  options.modules.discord.enable = lib.mkEnableOption "shared Discord configuration";

  config = lib.mkIf config.modules.discord.enable {
    modules.fcitx5.enable = true;
    home-manager.sharedModules = [ ./home.nix ];
  };
}
