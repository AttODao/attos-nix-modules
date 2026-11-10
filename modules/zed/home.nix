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
      # claude-agent-acp同梱のgeneric Linux向けbinaryはNixOSで起動できない。
      # remote projectではagentを接続先で起動するため、接続先のsettings.jsonにも必要。
      userSettings = lib.mkIf osConfig.modules.claude-code.enable (
        lib.mapAttrsRecursive (_: lib.mkDefault) {
          agent_servers.claude-acp = {
            type = "registry";
            env.CLAUDE_CODE_EXECUTABLE = lib.getExe config.programs.claude-code.finalPackage;
          };
        }
      );
    };
  };
}
