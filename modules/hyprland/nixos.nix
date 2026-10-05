{ config, lib, ... }:
let
  cfg = config.modules.hyprland;
in
{
  config = lib.mkIf cfg.enable {
    programs = {
      dconf.enable = true;
      hyprland = {
        enable = true;
        withUWSM = true;
      };
    };

    services.logind.settings.Login = {
      HandlePowerKey = "ignore";
      HandlePowerKeyLongPress = "ignore";
    }
    // lib.optionalAttrs cfg.lidSwitch.enable {
      HandleLidSwitch = "ignore";
      HandleLidSwitchExternalPower = "ignore";
      HandleLidSwitchDocked = "ignore";
    };

    services.gvfs.enable = true;
  };
}
