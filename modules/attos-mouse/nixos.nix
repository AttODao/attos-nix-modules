{ config, lib, ... }:
{
  config = lib.mkIf config.modules.attos-mouse.enable {
    hardware.logitech.wireless.enable = true;
  };
}
