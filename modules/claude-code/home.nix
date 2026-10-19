{
  osConfig,
  lib,
  pkgs,
  attopkgs,
  ...
}:
let
  cfg = osConfig.modules.claude-code;
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
      lspServers = lib.filterAttrs (name: _: cfg.lsp.${name}.enable) {
        nixd = {
          command = lib.getExe pkgs.nixd;
          extensionToLanguage.".nix" = "nix";
        };
        rust-analyzer = {
          command = lib.getExe pkgs.rust-analyzer;
          extensionToLanguage.".rs" = "rust";
        };
        gopls = {
          command = lib.getExe pkgs.gopls;
          args = [ "serve" ];
          extensionToLanguage.".go" = "go";
        };
      };
    };

    # MCP不在時のskill fallbackはcontext-mode CLIを使う。
    home.packages = lib.optional cfg.contextMode.enable attopkgs.context-mode;
  };
}
