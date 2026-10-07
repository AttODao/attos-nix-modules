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
      environmentFile = ps.pathOption "Runtime password environment file (PASSWORD or HASHED_PASSWORD); required for local password authentication. Decryption, permissions and restart ordering belong to the consumer.";
    }
  );

  config.assertions = selected.assertions;
}
