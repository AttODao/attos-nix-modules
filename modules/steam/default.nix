{ config, lib, ... }:
{
  imports = [
    ./nixos.nix
    ../pcmanfm
  ];

  options.modules.steam.enable = lib.mkEnableOption "shared Steam configuration";

  config = lib.mkIf config.modules.steam.enable {
    modules.pcmanfm.enable = true;
    home-manager.sharedModules = [ ./home.nix ];
  };
}
