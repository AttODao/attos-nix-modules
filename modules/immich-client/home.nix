{
  osConfig,
  lib,
  pkgs,
  ...
}:
let
  cfg = osConfig.modules.immich-client;
in
{
  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.immich-cli ];

    systemd.user.services.immich-upload = {
      Unit = {
        Description = "Immich upload watcher";
        # Stay inactive until `immich login` has written the user's credentials.
        ConditionPathExists = "%h/.config/immich/auth.yml";
        After = [ "network-online.target" ];
      };

      Service = {
        ExecStart = lib.escapeShellArgs (
          [
            (lib.getExe pkgs.immich-cli)
            "upload"
            "--recursive"
            "--watch"
            "--no-progress"
          ]
          ++ cfg.watchDirectories
        );
        Restart = "on-failure";
        RestartSec = 30;
      };

      Install.WantedBy = [ "default.target" ];
    };
  };
}
