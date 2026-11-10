{
  lib,
  ps,
  ...
}:
let
  inherit (lib) mkOption types;
in
{
  imports = [ ./nixos.nix ];

  options.modules.ytdl-sub = {
    enable = lib.mkEnableOption "the shared ytdl-sub downloads";
    dataDir = ps.pathOption "Consumer-owned mutable root containing YouTube, Twitch and the working directory.";
    cookieFile = ps.pathOption "Consumer-owned runtime cookie file, writable by the service user because yt-dlp updates it; never read into the Nix store.";
    startConditionFile = ps.pathOption "Optional runtime file that must exist before downloads start; null disables the condition.";
    subscriptions = mkOption {
      type = types.attrsOf (types.attrsOf types.anything);
      default = { };
      description = "ytdl-sub subscription documents by instance name (for example youtube, twitch); each instance becomes ytdl-sub-<name>.service, run every three hours at minute 15. At least one is required. Use real host paths below dataDir, and cookieFile for cookies; the documents enter the Nix store, so keep secrets out.";
    };
    user = mkOption {
      type = types.nonEmptyStr;
      default = "ytdl-sub";
      description = "Account running the downloads and owning dataDir; it must be able to write cookieFile. A custom account is created by the consumer.";
    };
    group = mkOption {
      type = types.nonEmptyStr;
      default = "ytdl-sub";
      description = "Group owning dataDir.";
    };
  };
}
