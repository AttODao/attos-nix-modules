{ config, lib, ... }:
{
  options.modules.amazon-music.enable = lib.mkEnableOption "shared Amazon Music (Windows app in Wine) configuration";

  config = lib.mkIf config.modules.amazon-music.enable {
    home-manager.sharedModules = [ ./home.nix ];
  };
}
