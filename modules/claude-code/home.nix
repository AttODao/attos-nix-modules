{
  osConfig,
  lib,
  pkgs,
  attopkgs,
  ...
}:
let
  cfg = osConfig.modules.claude-code;
  # skillのrevision/hashはPiと同じcatalogで固定する。
  resources = import ../pi/resources.nix { inherit pkgs lib attopkgs; };
in
{
  # settings.jsonは/model等のruntime変更を保持するため管理しない。認証も触らない。
  config = lib.mkIf osConfig.modules.claude-code.enable {
    programs.claude-code = {
      enable = true;
      package = attopkgs.claude-code;
      mcpServers = lib.mkIf cfg.contextMode.enable {
        context-mode.command = lib.getExe' attopkgs.context-mode "context-mode";
      };
      skills = lib.mapAttrs (name: _: lib.mkDefault resources.skills.${name}) (
        lib.filterAttrs (_: skill: skill.enable) cfg.skills
      );
    };

    # MCP不在時のskill fallbackはcontext-mode CLIを使う。
    home.packages = lib.optional cfg.contextMode.enable attopkgs.context-mode;
  };
}
