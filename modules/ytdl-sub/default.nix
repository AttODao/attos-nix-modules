{ config, lib, ... }:
let
  inherit (lib) mkOption types;
  ps = import ../public-services/lib.nix { inherit lib; };
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
      description = "ytdl-sub subscription documents by instance name (for example youtube, twitch); each runs every three hours. Use real paths below dataDir and cookieFile.";
    };
    user = mkOption {
      type = types.nonEmptyStr;
      default = "ytdl-sub";
      description = "Existing account owning the downloads and the cookie file.";
    };
    group = mkOption {
      type = types.nonEmptyStr;
      default = "ytdl-sub";
      description = "Group of the downloads.";
    };
  };
}
