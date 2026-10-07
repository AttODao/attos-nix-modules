{
  config,
  lib,
  pkgs,
  ...
}:
let
  ps = import ../public-services/lib.nix { inherit lib; };
  selected = ps.select config "sunshine";
  steam = lib.getExe config.programs.steam.package;
  setsid = lib.getExe' pkgs.util-linux "setsid";
in
{
  config = lib.mkIf selected.enabled {
    services.sunshine = {
      enable = true;
      openFirewall = lib.mkDefault false;
      capSysAdmin = lib.mkDefault false;
      settings = lib.mapAttrs (_: lib.mkDefault) {
        sunshine_name = config.networking.hostName;
        csrf_allowed_origins = "https://${selected.hostname}";
        capture = "wlr";
        keyboard = "enabled";
        mouse = "enabled";
        native_pen_touch = "enabled";
      };
      applications.apps = lib.mkDefault [
        {
          name = "Desktop";
          image-path = "desktop.png";
        }
        {
          name = "Steam Big Picture";
          detached = [ "${setsid} ${steam} steam://open/bigpicture" ];
          prep-cmd = [
            {
              do = "";
              undo = "${setsid} ${steam} steam://close/bigpicture";
            }
          ];
          image-path = "steam.png";
        }
      ];
    };
    # Outputs, audio sinks, device permissions, headless units, ingress and
    # pairing/authentication state remain with the consumer.
  };
}
