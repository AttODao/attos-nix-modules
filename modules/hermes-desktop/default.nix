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
  };

  config = lib.mkIf config.modules.hermes-desktop.enable {
    assertions = [
      {
        assertion = config.modules.hermes-desktop.url != null;
        message = "modules.hermes-desktop.url must be set when modules.hermes-desktop.enable is true.";
      }
    ];
    home-manager.sharedModules = [ ./home.nix ];
  };
}
