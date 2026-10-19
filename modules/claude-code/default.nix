{
  config,
  lib,
  pkgs,
  attopkgs,
  ...
}:
let
  resources = import ../pi/resources.nix { inherit pkgs lib attopkgs; };
in
{
  options.modules.claude-code = {
    enable = lib.mkEnableOption "shared Claude Code configuration";
    # Pi catalogのうちClaude Codeで動くskillだけを選ぶ。pi-mermaid-studioはPiの
    # mermaid_diagram tool、ctx-upgradeはread-onlyなNix管理installの書換えに依存し、
    # find-skillsはnpxでNix管理外へskillを追加するため含めない。
    skills =
      lib.mapAttrs
        (name: _: {
          enable = lib.mkOption {
            type = lib.types.bool;
            default = true;
            description = "Enable the shared Claude Code skill ${name}.";
          };
        })
        (
          removeAttrs resources.skills [
            "pi-mermaid-studio"
            "ctx-upgrade"
            "find-skills"
          ]
        );
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
