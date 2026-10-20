{
  osConfig,
  config,
  lib,
  pkgs,
  ...
}:
let
  # Fcitx follows symlinks when saving; store-backed settings cannot persist changes.
  seeded = config.lib.attos.mutableXdgConfigFiles {
    name = "fcitx5";
    files.fcitx5 = [
      "config"
      "profile"
    ];
  };
in
{
  config = lib.mkIf osConfig.modules.fcitx5.enable {
    i18n.inputMethod = {
      enable = true;
      type = "fcitx5";
      fcitx5 = {
        waylandFrontend = lib.mkDefault true;
        addons = with pkgs; [
          fcitx5-gtk
          fcitx5-skk
          qt6Packages.fcitx5-configtool
        ];
        settings.globalOptions."Hotkey/AltTriggerKeys"."0" = lib.mkDefault "";
        settings.inputMethod = lib.mapAttrsRecursive (_: lib.mkDefault) {
          GroupOrder."0" = "Default";
          "Groups/0" = {
            "Name" = "Default";
            "Default Layout" = "us";
            "DefaultIM" = "skk";
          };
          "Groups/0/Items/0" = {
            "Name" = "skk";
            "Layout" = "us";
          };
          "Groups/0/Items/1" = {
            "Name" = "keyboard-us";
            "Layout" = osConfig.modules.fcitx5.keyboardLayout;
          };
        };
      };
    };

    xdg.configFile = lib.mkMerge [
      seeded.xdg.configFile
      {
        # Mask Home Manager's autostart entry so systemd remains the only launcher.
        "autostart/org.fcitx.Fcitx5.desktop".text = ''
          [Desktop Entry]
          Hidden=true
        '';
      }
    ];
    home.activation = seeded.home.activation;

    # GUI restart replaces the main process; keep its replacement in the service.
    systemd.user.services.fcitx5-daemon.Service.ExitType = "cgroup";
  };
}
