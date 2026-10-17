{ config, lib, ... }:
{
  options.modules.pandora-launcher.enable = lib.mkEnableOption "shared Pandora Launcher";

  config = lib.mkIf config.modules.pandora-launcher.enable {
    home-manager.sharedModules = [ ./home.nix ];
  };
}
