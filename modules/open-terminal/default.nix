{ config, lib, ... }:
let
  ps = import ../public-services/lib.nix { inherit lib; };
in
{
  imports = [
    ./nixos.nix
    ../docker
    ../swarm
  ];

  options.modules.open-terminal = {
    enable = lib.mkEnableOption "shared Open Terminal container configuration";

    dataDir = ps.pathOption "Runtime absolute path to the service root containing the workspace directory; required when enabled.";
    environmentFile = ps.pathOption "Runtime absolute path to the Open Terminal environment file; required when enabled. Secrets and file permissions are consumer-owned.";

    allowedOrigins = lib.mkOption {
      type = lib.types.nullOr lib.types.nonEmptyStr;
      default = null;
      description = "CORS origins string passed to OPEN_TERMINAL_CORS_ALLOWED_ORIGINS; required when enabled.";
    };

    uid = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.unsigned;
      default = null;
      description = "Numeric host UID owning the workspace, matching the container user or consumer's user-namespace mapping; required when enabled.";
    };
    gid = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.unsigned;
      default = null;
      description = "Numeric host GID owning the workspace, matching the container group or consumer's user-namespace mapping; required when enabled.";
    };
  };

  config = lib.mkIf config.modules.open-terminal.enable {
    modules.docker.enable = true;
    modules.swarm.enable = true;
  };
}
