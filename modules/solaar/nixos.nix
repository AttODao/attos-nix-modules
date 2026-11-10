{ config, lib, ... }:
{
  config = lib.mkIf config.modules.solaar.enable {
    programs.solaar = {
      enable = true;
      userService.enable = true;
    };
    # The upstream unit is only PartOf the session and restarts on failure; without these a
    # restart after logout would start Solaar with no display.
    systemd.user.services.solaar = {
      after = [ "graphical-session.target" ];
      requisite = [ "graphical-session.target" ];
    };
  };
}
