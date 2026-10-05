{
  osConfig,
  config,
  lib,
  pkgs,
  ...
}:
{
  config = lib.mkIf osConfig.modules.fcitx5.enable {
    i18n.inputMethod = {
      enable = true;
      type = "fcitx5";
      fcitx5 = {
        waylandFrontend = true;
        addons = with pkgs; [
          fcitx5-gtk
          fcitx5-skk
          qt6Packages.fcitx5-configtool
        ];
        settings.globalOptions."Hotkey/AltTriggerKeys"."0" = "";
        settings.inputMethod = {
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
            "Layout" = "";
          };
        };
      };
    };

    # Fcitx follows symlinks when saving; store-backed settings cannot persist changes.
    xdg.configFile.fcitx5.enable = false;
    home.activation.installFcitx5Config = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      run ${pkgs.coreutils}/bin/install -d -m 700 "${config.xdg.configHome}/fcitx5"
      run ${pkgs.coreutils}/bin/install -m 600 ${config.xdg.configFile.fcitx5.source}/{config,profile} "${config.xdg.configHome}/fcitx5/"
    '';

    # GUI restart replaces the main process; keep its replacement in the service.
    systemd.user.services.fcitx5-daemon.Service.ExitType = "cgroup";

    # Mask Home Manager's autostart entry so systemd remains the only launcher.
    xdg.configFile."autostart/org.fcitx.Fcitx5.desktop".text = ''
      [Desktop Entry]
      Hidden=true
    '';
  };
}
