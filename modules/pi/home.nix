{
  osConfig,
  config,
  lib,
  pkgs,
  attopkgs,
  ...
}:
let
  cfg = osConfig.modules.pi;
  agentDir = config.programs.pi-coding-agent.configDir;
  resources = import ./resources.nix { inherit pkgs attopkgs; };
in
{
  config = lib.mkIf cfg.enable {
    programs.pi-coding-agent = {
      enable = true;
      package = attopkgs.pi;
      extraPackages = [
        pkgs.bun
        pkgs.git
        pkgs.tmux
      ]
      ++ lib.optional cfg.plugins.context-mode.enable attopkgs.context-mode;
      # listは利用側の定義と結合する（packages・defaultToolsへ追加できる）。
      settings = {
        packages = lib.optional cfg.plugins.pi-mcp-adapter.enable resources.plugins.pi-mcp-adapter.package;
        defaultTools = [
          "read"
          "grep"
          "find"
          "ls"
          "bash"
          "edit"
          "write"
          "codemode"
        ]
        ++ lib.optional cfg.plugins.pi-mermaid-studio.enable "mermaid_diagram";
        sessions.autoTitle.refreshTurns = lib.mkDefault 4;
      };
      context = lib.mkDefault (
        builtins.readFile ./AGENTS.md
        + lib.optionalString cfg.plugins.pi-mermaid-studio.enable (
          "\n" + builtins.readFile ./mermaid-ssh.md
        )
      );
    };

    home.packages = [ pkgs.tmux ] ++ lib.optional cfg.plugins.context-mode.enable attopkgs.context-mode;
    # Load the bundled plugins through generated manifests that point at their original entry
    # points (so each resolves its own runtime dependencies), independent of settings.json.
    home.file = lib.mapAttrs' (
      name: plugin:
      lib.nameValuePair "${agentDir}/extensions/${name}" {
        enable = cfg.plugins.${name}.enable;
        source = lib.mkDefault (
          pkgs.writeTextDir "package.json" (
            builtins.toJSON {
              pi = {
                extensions = [ "${plugin.source}/${plugin.entry}" ];
                skills = [ ];
              };
            }
          )
        );
      }
    ) (lib.filterAttrs (_: plugin: plugin ? source) resources.plugins);
  };
}
