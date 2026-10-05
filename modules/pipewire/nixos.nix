{ config, lib, ... }:
{
  config = lib.mkIf config.modules.pipewire.enable {
    security.rtkit.enable = true;

    services.pipewire = {
      enable = true;
      alsa.enable = true;
      pulse.enable = true;
    };
  };
}
