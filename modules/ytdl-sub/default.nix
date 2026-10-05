{ config, lib, ... }:
let
  inherit (lib) mkOption types;
  ps = import ../public-services/lib.nix { inherit lib; };
  pathOption = ps.pathOption;
  configFile =
    description:
    mkOption {
      type = types.nullOr types.path;
      default = null;
      inherit description;
    };
in
{
  imports = [ ./nixos.nix ];

  options.modules.ytdl-sub = {
    enable = lib.mkEnableOption "the shared Docker ytdl-sub service";
    dataDir = pathOption "Consumer-owned mutable root; retains config, YouTube, Twitch and working-directory layout. Absolute string, without a Docker bind-mount colon.";
    cookieFile = pathOption "Consumer-owned runtime cookie file; never read into the Nix store. Readiness and rotation restarts belong to the caller.";
    subscriptionFiles = {
      youtube = configFile "Consumer-supplied YouTube subscription YAML file, copied at runtime; do not pass secret contents through Nix.";
      twitch = configFile "Consumer-supplied Twitch subscription YAML file, copied at runtime; do not pass secret contents through Nix.";
    };
    uid = mkOption {
      type = types.nullOr types.ints.unsigned;
      default = null;
      description = "Consumer-supplied numeric owner and container PUID.";
    };
    gid = mkOption {
      type = types.nullOr types.ints.unsigned;
      default = null;
      description = "Consumer-supplied numeric group and container PGID.";
    };
    cronFile = configFile "Optional caller cron script. Default runs YouTube then Twitch on the legacy three-hour OCI schedule; it intentionally retains the legacy last-command exit status and permits overlapping invocations.";
  };

  config = lib.mkIf config.modules.ytdl-sub.enable {
    modules.docker.enable = true;
  };
}
