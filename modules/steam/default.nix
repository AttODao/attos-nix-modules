{ config, lib, ... }:
{
  imports = [
    ./nixos.nix
    ../pcmanfm
  ];

  options.modules.steam = {
    enable = lib.mkEnableOption "shared Steam configuration";
    firewall = {
      remotePlay = lib.mkEnableOption "Steam Remote Play firewall ports";
      dedicatedServer = lib.mkEnableOption "Steam dedicated server firewall ports";
      localNetworkGameTransfers = lib.mkEnableOption "Steam local network transfer firewall ports";
    };
  };

  config = lib.mkIf config.modules.steam.enable {
    modules.pcmanfm.enable = true;
    home-manager.sharedModules = [ ./home.nix ];
  };
}
