{ config, lib, ... }:
{
  config = lib.mkIf config.modules.thunderbird.enable {
    services.gnome = {
      evolution-data-server.enable = true;
      gnome-keyring.enable = true;
    };
  };
}
