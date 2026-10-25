{ config, lib, ... }:
{
  options.modules.hermes-desktop = {
    enable = lib.mkEnableOption "Hermes Desktop as a remote-only client without a local backend";
    url = lib.mkOption {
      type = lib.types.nullOr (lib.types.strMatching "https?://[^[:space:]]+");
      default = null;
      example = "https://hermes.example.org";
      description = "Remote Hermes dashboard URL. Written as the initial connection only when the app has no connection settings yet; sign-in happens in the app and is never managed declaratively.";
    };
    ssh = lib.mkOption {
      type = lib.types.nullOr (lib.types.strMatching "[^@[:space:]]+@[^@[:space:]]+");
      default = null;
      example = "hermes@hermes.example.org";
      description = "SSH target (user@host[:port]) of the remote Hermes, written as the initial connection only when the app has no connection settings yet. The app starts its own dashboard over SSH with the user's SSH key.";
    };
  };

  config = lib.mkIf config.modules.hermes-desktop.enable {
    assertions = [
      {
        assertion =
          (config.modules.hermes-desktop.url != null) != (config.modules.hermes-desktop.ssh != null);
        message = "modules.hermes-desktop: set exactly one of url or ssh.";
      }
    ];
    home-manager.sharedModules = [ ./home.nix ];
  };
}
