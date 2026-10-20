{
  osConfig,
  config,
  lib,
  pkgs,
  ...
}:
{
  config = lib.mkIf osConfig.modules.opencloud-client.enable {
    home.packages = [ pkgs.opencloud-desktop ];

    xdg = {
      # Mask both upstream autostart names so systemd remains the only launcher.
      configFile."autostart/OpenCloud.desktop".text = ''
        [Desktop Entry]
        Type=Application
        Name=OpenCloud Desktop
        Hidden=true
      '';

      configFile."autostart/OpenCloud.desktop.backup" = {
        force = true;
        text = ''
          [Desktop Entry]
          Type=Application
          Name=OpenCloud Desktop
          Hidden=true
        '';
      };

      dataFile."applications/opencloudcmd.desktop".text = ''
        [Desktop Entry]
        Type=Application
        Name=OpenCloud Desktop
        Hidden=true
      '';
    };

    systemd.user.services.opencloud = config.lib.attos.graphicalAppService {
      description = "OpenCloud desktop client";
      exec = "${pkgs.opencloud-desktop}/bin/opencloud";
    };
  };
}
