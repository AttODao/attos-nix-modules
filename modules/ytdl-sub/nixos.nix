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
  # CRON_SCRIPT must be executable inside the container.
  cron = pkgs.writeScript "ytdl-sub-cron" (builtins.readFile ./cron);
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
      # The only legacy cleanup: obsolete generated files. Never touch media, archives or history.
      "r ${quotePath "${root}/config/config-twitch.yaml"}"
      "r ${quotePath "${root}/config/subscriptions.yaml"}"
      "d ${quotePath "${root}/YouTube"} 0755 ${uid} ${gid} -"
      "d ${quotePath "${root}/Twitch"} 0755 ${uid} ${gid} -"
    ];

    systemd.services.${container.serviceName} = {
      unitConfig = {
        ConditionPathExists = lib.mkIf (cfg.startConditionFile != null) cfg.startConditionFile;
        # Docker would create a missing bind source as a directory; fail instead.
        AssertPathExists = [
          cookie
          (toString youtube)
          (toString twitch)
        ];
        RequiresMountsFor = [
          root
          cookie
        ];
      };
    };

    virtualisation.oci-containers.containers.ytdl-sub = {
      # Review image/tool updates together; startup must use the packaged yt-dlp.
      image = lib.mkDefault "ghcr.io/jmbannon/ytdl-sub:2026.08.26.post1@sha256:f96bcf1d2896da0177f9c7964407c27830571d1eb96a5886abd605140c69e278";
      pull = lib.mkDefault "always";
      environment = lib.mapAttrs (_: lib.mkDefault) {
        PUID = uid;
        PGID = gid;
        TZ = "Asia/Tokyo";
        CRON_SCHEDULE = "15 */3 * * *";
        CRON_RUN_ON_START = "false";
        CRON_SCRIPT = "/config/cron";
        UPDATE_YT_DLP_ON_START = "";
      };
      autoRemoveOnStop = lib.mkDefault false;
      extraOptions = [ "--restart=unless-stopped" ];
      volumes = [
        "/etc/localtime:/etc/localtime:ro"
        "${root}:/ytdl-sub"
        "${root}/config:/config"
        "${cookie}:/config/cookies.txt"
        "${commonConfig}:/config/config.yaml:ro"
        "${toString youtube}:/config/subscriptions-youtube.yaml:ro"
        "${toString twitch}:/config/subscriptions-twitch.yaml:ro"
        "${cron}:/config/cron:ro"
      ];
    };
  };
}
