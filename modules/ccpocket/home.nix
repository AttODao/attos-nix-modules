{
  osConfig,
  config,
  lib,
  pkgs,
  attopkgs,
  ps,
  ...
}:
let
  selected = ps.select osConfig "ccpocket";
  cfg = selected.cfg;
  # Standalone stays on loopback; a public owner listens on its same-hostname SSH address.
  listenAddress =
    if selected.standalone then
      "127.0.0.1"
    else
      osConfig.modules.public-services.${selected.hostname}.ssh.address;
  userHome = config.home.homeDirectory;
  environmentFile =
    if cfg.environmentFile == null then "${userHome}/.ccpocket/bridge.env" else cfg.environmentFile;
  bridge = attopkgs.ccpocket-bridge;
in
{
  config = lib.mkIf selected.enabled {
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
          "BRIDGE_HOST=${listenAddress}"
          "BRIDGE_PORT=${toString cfg.port}"
          # mDNS only reaches the local LAN; clients connect by address.
          "BRIDGE_DISABLE_MDNS=1"
          # Keep BRIDGE_API_KEY out of the startup deep link/QR printed to the journal.
          "BRIDGE_DEMO_MODE=1"
        ]
        # The startup URL/QR uses the registered hostname instead of the LAN addresses.
        # Plain ws://: the hostname must resolve only inside the private DNS/VPN network.
        ++ lib.optional (
          !selected.standalone
        ) "BRIDGE_PUBLIC_WS_URL=ws://${selected.hostname}:${toString cfg.port}"
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
        # The bridge gives shell access, so refuse to start unauthenticated.
        ExecStartPre = "${pkgs.writeShellScript "ccpocket-bridge-require-api-key" ''
          if [ -z "''${BRIDGE_API_KEY:-}" ]; then
            echo "BRIDGE_API_KEY is not set in ${environmentFile}" >&2
            exit 1
          fi
        ''}";
        ExecStart = lib.getExe bridge;
        # Also retries until the listen address exists after boot.
        Restart = "on-failure";
        RestartSec = "5s";
        UMask = "0077";
      };
    };
  };
}
