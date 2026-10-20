{
  config,
  lib,
  ps,
  ...
}:
let
  cfg = config.modules.ytdl-sub;
  root = ps.require "ytdl-sub" "dataDir" cfg.dataDir;
  cookie = ps.require "ytdl-sub" "cookieFile" cfg.cookieFile;
in
{
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.subscriptions != { };
        message = "modules.ytdl-sub.subscriptions must define at least one instance.";
      }
    ];

    systemd.tmpfiles.settings."10-ytdl-sub" = {
      ${root}.d = {
        mode = "0755";
        inherit (cfg) user group;
      };
      "${root}/.ytdl-sub-working-directory".d = {
        mode = "0755";
        inherit (cfg) user group;
      };
    };

    services.ytdl-sub = {
      inherit (cfg) user group;
      instances = lib.mapAttrs (name: subscriptions: {
        enable = true;
        schedule = "*-*-* 00/3:15:00";
        readWritePaths = [
          root
          cookie
        ];
        # Stage large downloads on the data disk, not the runtime tmpfs; one directory per instance.
        config.configuration.working_directory = lib.mkForce "${root}/.ytdl-sub-working-directory/${name}";
        inherit subscriptions;
      }) cfg.subscriptions;
    };

    systemd.services = lib.mapAttrs' (
      name: _:
      lib.nameValuePair "ytdl-sub-${name}" {
        unitConfig = {
          ConditionPathExists = lib.mkIf (cfg.startConditionFile != null) cfg.startConditionFile;
          RequiresMountsFor = [
            root
            cookie
          ];
        };
      }
    ) cfg.subscriptions;
  };
}
