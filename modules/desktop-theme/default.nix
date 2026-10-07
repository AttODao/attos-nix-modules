{ config, lib, ... }:
{
  imports = [ ../fcitx5 ];

  options.modules.desktop-theme.enable = lib.mkEnableOption "shared desktop theme configuration";

  config = lib.mkIf config.modules.desktop-theme.enable {
    modules.fcitx5.enable = true;
    home-manager.sharedModules = [ ./home.nix ];
  };
}
