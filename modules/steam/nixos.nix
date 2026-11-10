{ config, lib, ... }:
{
  config = lib.mkIf config.modules.steam.enable {
    programs.steam = {
      enable = true;
      remotePlay.openFirewall = lib.mkDefault config.modules.steam.firewall.remotePlay;
      dedicatedServer.openFirewall = lib.mkDefault config.modules.steam.firewall.dedicatedServer;
      localNetworkGameTransfers.openFirewall = lib.mkDefault config.modules.steam.firewall.localNetworkGameTransfers;
    };
    # Allowing the unfree Steam packages stays with the consumer.
  };
}
