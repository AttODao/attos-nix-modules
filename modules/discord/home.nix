{
  osConfig,
  config,
  lib,
  pkgs,
  ...
}:
{
  config = lib.mkIf osConfig.modules.discord.enable {
    programs.discord = {
      enable = true;
      package = lib.mkIf (osConfig.modules.discord.commandLineArgs != "") (
        lib.mkDefault (
          pkgs.discord.override {
            commandLineArgs = osConfig.modules.discord.commandLineArgs;
          }
        )
      );
    };

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
        KillMode = lib.mkDefault osConfig.modules.discord.service.killMode;
        Restart = "on-failure";
        RestartSec = 3;
      };

      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
