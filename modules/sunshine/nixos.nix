{
  config,
  lib,
  pkgs,
  ...
}:
let
  ps = import ../public-services/lib.nix { inherit lib; };
  selected = ps.select config "sunshine";
  cfg = selected.cfg;
  steam = lib.getExe config.programs.steam.package;
  setsid = lib.getExe' pkgs.util-linux "setsid";
in
{
  config = lib.mkIf selected.enabled {
    services.sunshine = {
      enable = true;
      openFirewall = lib.mkDefault false;
      capSysAdmin = lib.mkDefault false;
      settings = lib.mapAttrs (_: lib.mkDefault) (
        {
          sunshine_name = config.networking.hostName;
          csrf_allowed_origins = "https://${selected.hostname}";
          capture = "wlr";
          keyboard = "enabled";
          mouse = "enabled";
          native_pen_touch = "enabled";
        }
        // cfg.settings
      );
      applications.apps = lib.mkDefault (
        if cfg.apps != null then
          map (app: lib.filterAttrs (_: value: value != null && value != [ ]) app) cfg.apps
        else
          [
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
          ]
      );
    };
    assertions = [
      {
        assertion = !cfg.waitForHeadlessOutput || config.modules.hyprland.headless.enable;
        message = "Sunshine waitForHeadlessOutput requires modules.hyprland.headless.enable on the owning OS.";
      }
    ];
    systemd.user.services.sunshine = lib.mkIf cfg.waitForHeadlessOutput {
      requires = [ "hyprland-headless-output.service" ];
      after = [ "hyprland-headless-output.service" ];
    };
    # Hardware, permissions, ingress and pairing/authentication state remain consumer-owned.
  };
}
