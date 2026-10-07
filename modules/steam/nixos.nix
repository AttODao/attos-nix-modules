{ config, lib, ... }:
{
  config = lib.mkIf config.modules.steam.enable {
    programs.steam.enable = true;
    # Firewall openings and unfree permission are consumer policies.
  };
}
