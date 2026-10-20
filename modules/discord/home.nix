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

    systemd.user.services.discord = config.lib.attos.graphicalAppService {
      description = "Discord desktop client";
      exec = "${config.programs.discord.package}/bin/discord --start-minimized";
      wantsFcitx = true;
      restartSec = 3;
      killMode = osConfig.modules.discord.service.killMode;
    };
  };
}
