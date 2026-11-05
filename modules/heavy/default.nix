{
  config,
  lib,
  attopkgs,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.modules.heavy;
  size = types.strMatching "[0-9]+[KMGT]?|infinity";
in
{
  options.modules.heavy = {
    enable = lib.mkEnableOption "the heavy command: per-host serialization and memory limits for heavy jobs, with dispatch to a larger host";
    memoryHigh = mkOption {
      type = size;
      default = "4G";
      description = "MemoryHigh of the scope that runs a local heavy job.";
    };
    memoryMax = mkOption {
      type = size;
      default = "6G";
      description = "MemoryMax of the scope that runs a local heavy job.";
    };
    remotes = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            name = mkOption {
              type = types.strMatching "[a-z0-9][a-z0-9-]*";
              description = "Name used by --remote and HEAVY_HOST.";
            };
            ssh = mkOption {
              type = types.nonEmptyStr;
              description = "SSH destination; the calling user's SSH configuration and keys are used.";
            };
          };
        }
      );
      default = [ ];
      description = "Hosts tried in order by `heavy run --auto`; the first reachable one runs the job. Each remote needs modules.heavy enabled too.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ attopkgs.heavy ];
    environment.etc."heavy/config.json".text = builtins.toJSON {
      lockFile = "/run/heavy/lock";
      ownerFile = "/run/heavy/owner";
      # Written by attos-jobs pause; while it exists this host refuses heavy jobs.
      pauseFile = "/run/heavy/paused";
      inherit (cfg) memoryHigh memoryMax;
      remotes = map (r: { inherit (r) name ssh; }) cfg.remotes;
      oomScoreAdjust = 1000;
      remoteDir = ".cache/heavy";
      excludes = [
        ".git"
        "target"
        "result"
        "node_modules"
        ".direnv"
        ".devenv"
      ];
    };
    # Every local user shares one lock per host.
    systemd.tmpfiles.settings."10-heavy" = {
      "/run/heavy".d = {
        mode = "0755";
        user = "root";
        group = "root";
      };
      "/run/heavy/lock".f = {
        mode = "0666";
        user = "root";
        group = "root";
      };
      "/run/heavy/owner".f = {
        mode = "0666";
        user = "root";
        group = "root";
      };
    };
  };
}
