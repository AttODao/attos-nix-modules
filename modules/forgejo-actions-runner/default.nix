{ config, lib, ... }:
let
  ps = import ../public-services/lib.nix { inherit lib; };
in
{
  imports = [
    ./nixos.nix
    ../docker
  ];

  options.modules.forgejo-actions-runner = {
    enable = lib.mkEnableOption "shared Forgejo Actions runner";
    tokenFile = ps.pathOption "Absolute runtime path to the native runner's registration environment file containing TOKEN; required when enabled.";
    dataDir = ps.pathOption "Absolute runtime path to a dedicated persistent runner directory, containing .runner, .labels and .token-hash; required when enabled. Existing state and its ownership must be migrated by the consumer.";
  };

  config = lib.mkIf config.modules.forgejo-actions-runner.enable {
    modules.docker.enable = true;
  };
}
