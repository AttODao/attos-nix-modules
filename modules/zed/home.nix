{
  config,
  osConfig,
  lib,
  ...
}:
{
  config = lib.mkIf osConfig.modules.zed.enable {
    programs.zed-editor = {
      enable = true;
      package = lib.mkIf (!osConfig.modules.zed.installEditor) null;
      userSettings = lib.mkMerge [
        (lib.mkDefault osConfig.modules.zed.userSettings)
        # claude-agent-acp同梱のgeneric Linux向けbinaryはNixOSで起動できない。
        # remote projectではagentを接続先で起動するため、接続先のsettings.jsonにも必要。
        (lib.mkIf osConfig.modules.claude-code.enable (
          lib.mkDefault {
            agent_servers.claude-acp = {
              type = "registry";
              env.CLAUDE_CODE_EXECUTABLE = lib.getExe config.programs.claude-code.finalPackage;
            };
          }
        ))
      ];
    };

    home.file.".local/share/zed/external_agents/registry/npx/codex-acp/.npmrc" =
      lib.mkIf (osConfig.modules.zed.codexAcp.npmPolicy == "bounded-offline")
        {
          text = ''
            audit=false
            fetch-retries=1
            fetch-retry-maxtimeout=5000
            fetch-retry-mintimeout=1000
            fetch-timeout=10000
            prefer-offline=true
          '';
        };
  };
}
