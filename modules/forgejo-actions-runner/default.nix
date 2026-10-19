{ config, lib, ... }:
let
  ps = import ../public-services/lib.nix { inherit lib; };
  cfg = config.modules.forgejo-actions-runner;
in
{
  imports = [
    ./nixos.nix
    ../docker
  ];

  options.modules.forgejo-actions-runner = {
    enable = lib.mkEnableOption "shared Forgejo Actions runner inside an Incus KVM VM guest";
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
  };

  config = lib.mkIf (cfg.enable && cfg.docker) {
    modules.docker.enable = true;
  };
}
