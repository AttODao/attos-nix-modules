{ config, lib, ... }:
let
  cfg = config.modules.ccpocket;
in
{
  options.modules.ccpocket = {
    enable = lib.mkEnableOption "shared CC Pocket Bridge Server user service";
    port = lib.mkOption {
      type = lib.types.port;
      default = 8765;
      description = "WebSocket port the bridge listens on (all addresses); the consumer opens its firewall.";
    };
    environmentFile =
      (import ../public-services/lib.nix { inherit lib; }).pathOption
        "Runtime environment file with BRIDGE_API_KEY and Claude/Codex credentials; null uses each user’s ~/.ccpocket/bridge.env.";
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = builtins.length (builtins.attrNames config.home-manager.users) <= 1;
        message = "modules.ccpocket: the bridge listens on one fixed port, so at most one Home Manager user is supported.";
      }
    ];
    home-manager.sharedModules = [ ./home.nix ];
  };
}
