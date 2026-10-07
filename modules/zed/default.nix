{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.modules.zed = {
    enable = lib.mkEnableOption "shared Zed editor configuration";
    userSettings = lib.mkOption {
      type = (pkgs.formats.json { }).type;
      default = { };
      description = "Shared Zed user settings, applied as overridable defaults to all HM users. Keep credentials out of these store-backed values.";
    };
    codexAcp.npmPolicy = lib.mkOption {
      type = lib.types.enum [
        "default"
        "bounded-offline"
      ];
      default = "default";
      description = "Default leaves npm policy unmanaged. Bounded-offline disables audit, prefers cached downloads, and limits retries/timeouts for Zed's codex-acp npx registry.";
    };
  };

  config = lib.mkIf config.modules.zed.enable {
    home-manager.sharedModules = [ ./home.nix ];
  };
}
