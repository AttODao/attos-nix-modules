{ config, lib, ... }:
let
  ps = import ../public-services/lib.nix { inherit lib; };
  selected = ps.select config "code-server";
in
{
  imports = [ ./nixos.nix ];

  options.modules.public-services = ps.option "code-server" (
    ps.common "code-server web development environment"
    // {
      backendUrl = lib.mkOption {
        type = lib.types.nullOr lib.types.nonEmptyStr;
        default = null;
        description = "HTTP(S) upstream reachable by the gateway; required when enabled, including local deployment.";
      };
      packageSource = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Consumer-pinned extracted standalone release directory; when supplied, package with attopkgs.code-server (including its Nerd Font). Null retains the host package.";
      };
      user = lib.mkOption {
        type = lib.types.nonEmptyStr;
        default = "code-server";
        description = "Existing account running code-server; custom accounts remain consumer-owned.";
      };
      group = lib.mkOption {
        type = lib.types.nonEmptyStr;
        default = "code-server";
        description = "Existing group running code-server; custom groups remain consumer-owned.";
      };
      environmentFile = ps.pathOption "Runtime password environment file (PASSWORD or HASHED_PASSWORD); required for local password authentication. Decryption, permissions and restart ordering belong to the consumer.";
    }
  );

  config.assertions = selected.assertions;
}
