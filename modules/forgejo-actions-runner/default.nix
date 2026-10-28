{
  config,
  lib,
  ps,
  ...
}:
let
  cfg = config.modules.forgejo-actions-runner;
in
{
  imports = [
    ./nixos.nix
    ../docker
  ];

  options.modules.forgejo-actions-runner = {
    enable = lib.mkEnableOption "shared Forgejo Actions runner on this host (jobs in Docker containers)";
    url = lib.mkOption {
      type = lib.types.nullOr lib.types.nonEmptyStr;
      default = null;
      example = "https://git.example.org";
      description = "Forgejo base URL the runner connects to. Null derives it from the public-services forgejo registry (the standalone instance or the single registered hostname).";
    };
    fetchInterval = lib.mkOption {
      type = lib.types.nullOr (lib.types.strMatching "[0-9]+(ms|s|m)");
      default = null;
      example = "30s";
      description = "runner.fetch_interval. Null keeps the runner default (2s). A longer interval lets another runner with the same labels that polls faster take queued jobs first, so this runner mainly picks up jobs while that one is offline or busy.";
    };
    jobLimits.cpus = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = null;
      example = 4;
      description = "Docker --cpus for every job container; null leaves it unlimited.";
    };
    jobLimits.memory = lib.mkOption {
      type = lib.types.nullOr (lib.types.strMatching "[0-9]+[kmg]");
      default = null;
      example = "6g";
      description = "Docker --memory (and the same --memory-swap, so jobs do not swap) for every job container; null leaves it unlimited.";
    };
    uuid = lib.mkOption {
      type = lib.types.nullOr lib.types.nonEmptyStr;
      default = null;
      description = "Runner UUID shown by Forgejo's \"Create new runner\"; required when enabled. Not a secret.";
    };
    tokenFile = ps.pathOption "Absolute runtime path to a file containing only the runner token paired with uuid; required when enabled.";
    docker = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Run jobs in Docker containers (the default ubuntu-latest/docker labels). False leaves Docker off for host-only runners whose labels are set through the standard services.forgejo-runner option.";
    };
    dockerHost = lib.mkOption {
      type = lib.types.nullOr lib.types.nonEmptyStr;
      default = null;
      example = "automount";
      description = "container.docker_host for the runner. Null keeps the host Docker socket out of job containers (\"-\"); \"automount\" mounts it into every job and gives workflows root on the runner host.";
    };
  };

  config = lib.mkIf (cfg.enable && cfg.docker) {
    modules.docker.enable = true;
  };
}
