{
  config,
  lib,
  ps,
  ...
}:
let
  selected = ps.select config "code-server";
in
{
  imports = [ ./nixos.nix ];

  options.modules = ps.moduleOptions "code-server" (
    ps.common "code-server web development environment"
    // {
      backendUrl = lib.mkOption {
        type = lib.types.nullOr lib.types.nonEmptyStr;
        default = null;
        description = "Gateway upstream http://<address>:<port>; required when enabled, also for deploy = false. The owner binds code-server to this address and port.";
      };
      packageSource = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Consumer-pinned extracted standalone release directory, packaged with attopkgs.code-server (adds the JetBrainsMono Nerd Font to the workbench). Null keeps services.code-server.package.";
      };
      environmentFile = ps.pathOption "Runtime environment file with PASSWORD or HASHED_PASSWORD; required while services.code-server.auth is \"password\" (the default). Decryption, permissions and restart ordering belong to the consumer.";
    }
  );

  config.assertions = selected.assertions;
}
