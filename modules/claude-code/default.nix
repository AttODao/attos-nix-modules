{ config, lib, ... }:
{
  options.modules.claude-code = {
    enable = lib.mkEnableOption "shared Claude Code configuration";
    # Pi catalogのうちClaude Codeで動くskillだけを選ぶ。pi-mermaid-studioはPiの
    # mermaid_diagram tool、ctx-upgradeはread-onlyなNix管理installの書換えに依存し、
    # find-skillsはnpxでNix管理外へskillを追加するため含めない。
    skills =
      lib.genAttrs
        [
          "grilling"
          "improve-codebase-architecture"
          "ponytail"
          "ponytail-audit"
          "ponytail-debt"
          "ponytail-gain"
          "ponytail-help"
          "ponytail-review"
          "context-mode"
          "ctx-doctor"
          "ctx-index"
          "ctx-insight"
          "ctx-purge"
          "ctx-search"
          "ctx-stats"
        ]
        (name: {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable the shared Claude Code skill ${name}.";
          };
        });
    contextMode.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Register the context-mode MCP server whose tools the context-mode skills use.";
    };
    lsp = lib.genAttrs [ "nixd" "rust-analyzer" "gopls" ] (name: {
      enable = lib.mkEnableOption "the ${name} language server for Claude Code";
    });
  };

  config = lib.mkIf config.modules.claude-code.enable {
    home-manager.sharedModules = [ ./home.nix ];
  };
}
