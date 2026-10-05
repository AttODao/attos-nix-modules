{
  osConfig,
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = osConfig.modules.paseo;
  userHome = config.home.homeDirectory;
  paseoHome = "${userHome}/paseo";
  environmentFile =
    if cfg.environmentFile == null then "${paseoHome}/daemon.env" else cfg.environmentFile;
  paseoConfig = pkgs.writeText "paseo-config.json" (
    builtins.toJSON {
      "$schema" = "https://paseo.sh/schemas/paseo.config.v1.json";
      version = 1;
      daemon = {
        listen = "127.0.0.1:6767";
        hostnames = [ cfg.hostname ];
        mcp = {
          enabled = false;
          injectIntoAgents = false;
        };
        relay.enabled = true;
      };
      agents.providers = {
        claude.enabled = false;
        codex.enabled = false;
        copilot.enabled = false;
        omp.enabled = false;
        opencode.enabled = false;
        pi.enabled = true;
      };
      features = {
        dictation.enabled = false;
        voiceMode.enabled = false;
        webUi.enabled = false;
      };
    }
  );
  paseo = pkgs.writeShellApplication {
    name = "paseo";
    runtimeInputs = [ pkgs.nodejs ];
    text = ''
      exec npx --yes --prefer-online @getpaseo/cli@latest "$@"
    '';
  };
in
{
  config = lib.mkIf cfg.enable {
    home.packages = [ paseo ];
    systemd.user.services.paseo-daemon = {
      Unit = {
        Description = "Paseo daemon";
        ConditionPathExists = environmentFile;
      };
      Install.WantedBy = [ "default.target" ];
      Service = {
        WorkingDirectory = userHome;
        EnvironmentFile = environmentFile;
        Environment = [
          "HOME=${userHome}"
          "PASEO_HOME=${paseoHome}"
          "PI_CODING_AGENT_DIR=${config.programs.pi-coding-agent.configDir}"
          "NPM_CONFIG_CACHE=${paseoHome}/npm-cache"
          "NPM_CONFIG_UPDATE_NOTIFIER=false"
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
        ExecStartPre = pkgs.writeShellScript "paseo-install-config" ''
          set -eu
          ${pkgs.coreutils}/bin/install -d -m 0700 ${lib.escapeShellArg paseoHome}
          ${pkgs.coreutils}/bin/install -m 0600 ${paseoConfig} ${lib.escapeShellArg "${paseoHome}/config.json"}
        '';
        ExecStart = "${paseo}/bin/paseo daemon run --home ${lib.escapeShellArg paseoHome}";
        Restart = "on-failure";
        RestartSec = "5s";
        TimeoutStartSec = "5min";
        UMask = "0077";
      };
    };
  };
}
