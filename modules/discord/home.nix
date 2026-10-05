{
  osConfig,
  config,
  lib,
  ...
}:
{
  config = lib.mkIf osConfig.modules.discord.enable {
    programs.discord.enable = true;

    systemd.user.services.discord = {
      Unit = {
        Description = "Discord desktop client";
        Wants = [ "fcitx5-daemon.service" ];
        After = [
          "graphical-session.target"
          "fcitx5-daemon.service"
        ];
      };

      Service = {
        ExecStart = "${config.programs.discord.package}/bin/discord --start-minimized";
        Restart = "on-failure";
        RestartSec = 3;
      };

      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
