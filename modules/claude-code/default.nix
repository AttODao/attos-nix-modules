{
  config,
  lib,
  ...
}:
{
  imports = [ ../skills ];

  options.modules.claude-code = {
    enable = lib.mkEnableOption "shared Claude Code configuration";
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
    modules.skills.enable = true;
    home-manager.sharedModules = [ ./home.nix ];
  };
}
