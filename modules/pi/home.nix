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
  settings = pkgs.writeText "pi-settings.json" (
    builtins.toJSON config.programs.pi-coding-agent.settings
  );
  resources = import ./resources.nix { inherit pkgs lib attopkgs; };
in
{
  config = lib.mkIf osConfig.modules.pi.enable {
    programs.pi-coding-agent = {
      enable = true;
      package = attopkgs.pi;
      extraPackages = [
        pkgs.bun
        pkgs.git
        pkgs.tmux
      ]
      ++ lib.optional cfg.plugins.context-mode.enable attopkgs.context-mode;
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
        sessions.autoTitle.refreshTurns = 4;
      };
    };

    # declarativeから切り替えた場合も、旧generationのstore symlinkはlinkGenerationが先に削除する。
    home.activation.mergePiSettings = lib.mkIf (cfg.settingsMode == "merge") (
      lib.hm.dag.entryAfter [ "linkGeneration" ] (
        lib.hm.generators.mkImpureConfigMerger {
          inherit pkgs;
          format = "json";
          empty = "{}";
          mode = "600";
          path = "${agentDir}/settings.json";
          staticSettings = settings;
          # User values win; user package order is kept and missing module packages are appended.
          jqOperation = ''
            ($static * $dynamic)
            | if (.packages | type) == "array" then
                .packages = (
                  (($dynamic.packages // []) + ($static.packages // []))
                  | reduce .[] as $package ([]; if (map(. == $package) | any) then . else . + [$package] end)
                )
              else . end
          '';
        }
      )
    );

    home.packages = [ pkgs.tmux ] ++ lib.optional cfg.plugins.context-mode.enable attopkgs.context-mode;
    home.file = {
      "${agentDir}/settings.json".enable = lib.mkIf (cfg.settingsMode == "merge") false;
      "${agentDir}/AGENTS.md".text = lib.mkDefault (
        builtins.readFile ./AGENTS.md
        + lib.optionalString cfg.plugins.pi-mermaid-studio.enable (
          "\n" + builtins.readFile ./mermaid-ssh.md
        )
      );
    }
    # Nix-managed resource discovery must not depend on writable package settings.
    # Reference original entry points so their own runtime dependencies resolve.
    // lib.mapAttrs' (
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
