{
  config,
  lib,
  ps,
  ...
}:
let
  selected = ps.select config "ccpocket";
in
{
  options.modules = ps.moduleOptions "ccpocket" (
    ps.common "the shared CC Pocket Bridge user service"
    // {
      private = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Keep this hostname out of public CNAME records; the bridge is reached over the private network.";
      };
      port = lib.mkOption {
        type = lib.types.port;
        default = 8765;
        description = "WebSocket port; the consumer opens its firewall. The bridge speaks plain ws:// without TLS, so the listen address and the registered hostname must only be reachable over the private DNS/VPN network.";
      };
      allowClaudeOAuth = lib.mkEnableOption ''
        Claude sessions using this OS's Claude Code login (BRIDGE_ALLOW_CLAUDE_OAUTH=1)
        instead of ANTHROPIC_API_KEY; upstream marks this as an explicit opt-in'';
      environmentFile = ps.pathOption "Runtime environment file with BRIDGE_API_KEY and Claude/Codex credentials; null uses each user’s ~/.ccpocket/bridge.env.";
    }
  );

  config = lib.mkMerge [
    {
      # The hostname resolves to the SSH address in the local DNS; the owner listens there.
      assertions =
        selected.assertions
        ++ map (entry: {
          assertion = config.modules.public-services.${entry.hostname}.ssh.enable;
          message = "modules.public-services.${entry.hostname}.ccpocket requires an ssh record on the same hostname; its address is the bridge's DNS answer and listen address.";
        }) (ps.entries config "ccpocket");
    }
    (lib.mkIf selected.enabled {
      assertions = [
        {
          assertion = builtins.length (builtins.attrNames config.home-manager.users) <= 1;
          message = "ccpocket: the bridge listens on one fixed port, so at most one Home Manager user is supported.";
        }
      ];
      home-manager.sharedModules = [ ./home.nix ];
    })
  ];
}
