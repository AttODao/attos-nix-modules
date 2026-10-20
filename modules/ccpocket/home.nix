{
  osConfig,
  config,
  lib,
  pkgs,
  attopkgs,
  ...
}:
let
  cfg = osConfig.modules.ccpocket;
  userHome = config.home.homeDirectory;
  environmentFile =
    if cfg.environmentFile == null then "${userHome}/.ccpocket/bridge.env" else cfg.environmentFile;
  bridge = attopkgs.ccpocket-bridge;
in
{
  config = lib.mkIf cfg.enable {
    home.packages = [ bridge ];
    # Not `ccpocket-bridge setup`: it writes an unmanaged unit that runs `npx @latest`.
    systemd.user.services.ccpocket-bridge = {
      Unit = {
        Description = "CC Pocket Bridge Server";
        ConditionPathExists = environmentFile;
      };
      Install.WantedBy = [ "default.target" ];
      Service = {
        WorkingDirectory = userHome;
        EnvironmentFile = environmentFile;
        Environment = [
          "HOME=${userHome}"
          "BRIDGE_PORT=${toString cfg.port}"
          # mDNS only reaches the local LAN; clients connect by address.
          "BRIDGE_DISABLE_MDNS=1"
          # Keep BRIDGE_API_KEY out of the startup deep link/QR printed to the journal.
          "BRIDGE_DEMO_MODE=1"
        ]
        ++ lib.optional cfg.allowClaudeOAuth "BRIDGE_ALLOW_CLAUDE_OAUTH=1"
        ++ [
          # The agents run claude/codex/git from the user's profile.
          "PATH=${config.home.path}/bin:${
            lib.makeBinPath (
              with pkgs;
              [
                bash
                coreutils
                findutils
                git
                gnugrep
                gnused
                nodejs
                openssh
                procps
                ripgrep
              ]
            )
          }"
        ];
        # The bridge listens on every address and gives shell access, so refuse to start unauthenticated.
        ExecStartPre = "${pkgs.writeShellScript "ccpocket-bridge-require-api-key" ''
          if [ -z "''${BRIDGE_API_KEY:-}" ]; then
            echo "BRIDGE_API_KEY is not set in ${environmentFile}" >&2
            exit 1
          fi
        ''}";
        ExecStart = lib.getExe bridge;
        Restart = "on-failure";
        RestartSec = "5s";
        UMask = "0077";
      };
    };
  };
}
