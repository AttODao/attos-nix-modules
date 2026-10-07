{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.modules.ytdl-sub;
  require =
    field: value:
    if value == null then throw "ytdl-sub: ${field} must be supplied when enabled." else value;
  root = require "dataDir" cfg.dataDir;
  cookie = require "cookieFile" cfg.cookieFile;
  uid = toString (require "uid" cfg.uid);
  gid = toString (require "gid" cfg.gid);
  youtube = require "subscriptionFiles.youtube" cfg.subscriptionFiles.youtube;
  twitch = require "subscriptionFiles.twitch" cfg.subscriptionFiles.twitch;
  commonConfig = pkgs.writeText "ytdl-sub-config.yaml" (builtins.readFile ./config.yaml);
  cron = pkgs.writeText "ytdl-sub-cron" (builtins.readFile ./cron);
  container = config.virtualisation.oci-containers.containers.ytdl-sub;
  # tmpfiles fields support quoted paths; escape specifiers and control chars.
  quotePath =
    path:
    "\"${
      lib.replaceStrings [ "\\" "\"" "%" "\n" "\r" "\t" ] [ "\\\\" "\\\"" "%%" "\\n" "\\r" "\\t" ] path
    }\"";
in
{
  config = lib.mkIf cfg.enable {
    virtualisation.oci-containers.backend = lib.mkDefault "docker";
    assertions = [
      {
        assertion = config.virtualisation.oci-containers.backend == "docker";
        message = "ytdl-sub requires the Docker OCI backend.";
      }
    ];

    systemd.tmpfiles.rules = [
      "d ${quotePath root} 0755 root root -"
      "d ${quotePath "${root}/.ytdl-sub-working-directory"} 0755 ${uid} ${gid} -"
      "d ${quotePath "${root}/config"} 0700 ${uid} ${gid} -"
      "d ${quotePath "${root}/YouTube"} 0755 ${uid} ${gid} -"
      "d ${quotePath "${root}/Twitch"} 0755 ${uid} ${gid} -"
    ];

    systemd.services.ytdl-sub-config = {
      description = "Stage ytdl-sub configuration without replacing mutable state";
      unitConfig.RequiresMountsFor = [
        root
        cookie
      ];
      path = [ pkgs.coreutils ];
      environment = {
        YTDL_SUB_DATA_DIR = root;
        YTDL_SUB_COOKIE_FILE = cookie;
        YTDL_SUB_UID = uid;
        YTDL_SUB_GID = gid;
        YTDL_SUB_CONFIG_FILE = toString commonConfig;
        YTDL_SUB_YOUTUBE_FILE = toString youtube;
        YTDL_SUB_TWITCH_FILE = toString twitch;
        YTDL_SUB_CRON_FILE = toString cron;
      };
      restartTriggers = [
        commonConfig
        youtube
        twitch
        cron
      ];
      serviceConfig.Type = "oneshot";
      script = builtins.readFile ./stage-config.sh;
    };

    systemd.services.${container.serviceName} = {
      requires = [ "ytdl-sub-config.service" ];
      after = [ "ytdl-sub-config.service" ];
      unitConfig.RequiresMountsFor = [
        root
        cookie
      ];
    };

    virtualisation.oci-containers.containers.ytdl-sub = {
      image = lib.mkDefault "ghcr.io/jmbannon/ytdl-sub:latest";
      pull = lib.mkDefault "always";
      environment = lib.mapAttrs (_: lib.mkDefault) {
        PUID = uid;
        PGID = gid;
        TZ = "Asia/Tokyo";
        CRON_SCHEDULE = "15 */3 * * *";
        CRON_RUN_ON_START = "false";
        CRON_SCRIPT = "/config/cron";
        UPDATE_YT_DLP_ON_START = "stable";
      };
      autoRemoveOnStop = lib.mkDefault false;
      extraOptions = [ "--restart=unless-stopped" ];
      volumes = [
        "/etc/localtime:/etc/localtime:ro"
        "${root}:/ytdl-sub"
        "${root}/config:/config"
        "${cookie}:/config/cookies.txt"
      ];
    };
  };
}
