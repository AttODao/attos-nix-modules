{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.modules.hyprland;
  # Keep the compositor unchanged, but hide the unmanaged session in the greeter.
  # The UWSM session starts `uwsm start ... hyprland.desktop`, so the entry must stay
  # resolvable: uwsm rejects Hidden entries but accepts NoDisplay, which the greeter skips.
  # HM applies enableXWayland through .override; wrap that result as well.
  sessionPackage = lib.makeOverridable (
    {
      enableXWayland ? true,
    }:
    let
      package = pkgs.hyprland.override { inherit enableXWayland; };
    in
    pkgs.symlinkJoin {
      name = "hyprland-uwsm-only-${package.version}";
      inherit (package) pname version;
      meta = package.meta // {
        outputsToInstall = [ "out" ];
      };
      # Fold default documentation outputs into the single joined output.
      paths = map (output: package.${output}) (package.meta.outputsToInstall or [ "out" ]);
      postBuild = ''
        entry="$out/share/wayland-sessions/hyprland.desktop"
        source=$(readlink -f "$entry")
        rm "$entry"
        sed '/^\[Desktop Entry\]$/a NoDisplay=true' "$source" > "$entry"
        grep -qx 'NoDisplay=true' "$entry"
        grep -q ' hyprland.desktop$' "$out/share/wayland-sessions/hyprland-uwsm.desktop"
      '';
      passthru =
        package.passthru
        // lib.genAttrs (lib.remove "out" package.outputs) (output: package.${output})
        // {
          providedSessions = lib.remove "hyprland" (package.providedSessions or [ ]);
        };
    }
  ) { };
in
{
  config = lib.mkIf cfg.enable {
    programs = {
      dconf.enable = true;
      hyprland = {
        enable = true;
        withUWSM = true;
        package = lib.mkDefault sessionPackage;
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

    systemd.services = {
      # NixOS only marks logind reloadIfChanged; nothing reloads it when logind.conf changes,
      # so the new HandlePowerKey would stay unread until reboot. A reload trigger is enough.
      systemd-logind.reloadTriggers = [ config.environment.etc."systemd/logind.conf".source ];
    };
  };
}
