{
  config,
  lib,
  pkgs,
  utils,
  ...
}:
let
  cfg = config.modules.hyprland;
  hyprctl = lib.getExe' config.programs.hyprland.package "hyprctl";
  outputArgs = utils.escapeSystemdExecArgs;
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
      # Incus uses an ACPI power key event for graceful VM stop/restart.
      HandlePowerKey = if config.virtualisation.incus.agent.enable then "poweroff" else "ignore";
      HandlePowerKeyLongPress = "ignore";
    }
    // lib.optionalAttrs cfg.lidSwitch.enable {
      HandleLidSwitch = "ignore";
      HandleLidSwitchExternalPower = "ignore";
      HandleLidSwitchDocked = "ignore";
    };

    services.gvfs.enable = true;

    services.seatd = lib.mkIf cfg.headless.enable {
      enable = true;
      group = lib.mkDefault cfg.headless.seatGroup;
    };
    systemd.services = {
      systemd-logind.reloadTriggers = [ config.environment.etc."systemd/logind.conf".source ];
    }
    // lib.optionalAttrs cfg.headless.enable {
      seatd.environment.SEATD_VTBOUND = "0";
      container-udevd = lib.mkIf config.boot.isContainer {
        description = "Run udevd for dynamic input devices in the desktop container";
        wantedBy = [ "multi-user.target" ];
        after = [ "systemd-tmpfiles-setup.service" ];
        enableDefaultPath = false;
        serviceConfig = {
          Type = "notify-reload";
          ExecStart = "${pkgs.systemd}/lib/systemd/systemd-udevd";
          FileDescriptorStoreMax = 512;
          FileDescriptorStorePreserve = "yes";
          Restart = "on-failure";
        };
      };
    };
    systemd.tmpfiles.rules = lib.mkIf (cfg.headless.enable && config.boot.isContainer) (
      [ "d /dev/input 0755 root root -" ]
      ++ map (
        index:
        "c /dev/input/event${toString index} 0660 root ${cfg.headless.inputGroup} - 13:${toString (64 + index)}"
      ) (lib.range 0 63)
    );
    xdg.portal.config.common.default = lib.mkIf cfg.headless.enable (
      lib.mkDefault [
        "hyprland"
        "gtk"
      ]
    );
    systemd.user.services = lib.mkIf cfg.headless.enable {
      hyprland-bootstrap = {
        description = "Start the UWSM-managed Hyprland session";
        wantedBy = [ "default.target" ];
        restartIfChanged = false;
        enableDefaultPath = false;
        serviceConfig = {
          Environment = [
            "LIBSEAT_BACKEND=seatd"
            "XDG_SEAT=seat0"
            "XDG_SESSION_ID=headless"
            "XDG_VTNR=1"
          ];
          ExecStart = "${lib.getExe pkgs.uwsm} start -F -e -D Hyprland -- ${lib.getExe' config.programs.hyprland.package "start-hyprland"}";
          Restart = "always";
          RestartSec = "2s";
        };
      };
      hyprland-headless-output = {
        description = "Create the Hyprland output used by Sunshine";
        wantedBy = [ "graphical-session.target" ];
        partOf = [ "graphical-session.target" ];
        after = [ "graphical-session.target" ];
        enableDefaultPath = false;
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = outputArgs [
            hyprctl
            "output"
            "create"
            "headless"
            cfg.headless.outputName
          ];
          ExecStop =
            "-"
            + outputArgs [
              hyprctl
              "output"
              "remove"
              cfg.headless.outputName
            ];
        };
      };
    };
  };
}
