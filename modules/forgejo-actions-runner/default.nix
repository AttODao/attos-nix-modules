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
    dataDir = ps.pathOption "Absolute runtime path to persistent runner registration state; required when enabled. Never migrate existing state implicitly.";
    dynamicUser = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Keep the native DynamicUser and StateDirectory identity. Requires dataDir=/var/lib/gitea-runner/forgejo and disables static-user, tmpfiles and bind-mount plumbing.";
    };
    requiresMountsFor = lib.mkOption {
      type = lib.types.listOf ps.absolutePath;
      default = [ ];
      description = "Additional runtime mount paths required before registration and runner startup.";
    };
  };

  config = lib.mkIf config.modules.forgejo-actions-runner.enable {
    modules.docker.enable = true;
  };
}
