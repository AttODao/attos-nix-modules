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
  resources = import ./resources.nix {
    inherit pkgs lib attopkgs;
    inherit (cfg) piSessionsSource;
  };
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
        packages =
          lib.optional cfg.plugins.pi-mcp-adapter.enable resources.plugins.pi-mcp-adapter.package;
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

    # 旧generationのsymlinkがlinkGenerationで削除される前に引き継ぐ。
    home.activation.mergePiSettings = lib.mkIf (cfg.settingsMode == "merge") (
      lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ] ''
        (
          set -eu
          agentDir=${lib.escapeShellArg agentDir}
          run ${pkgs.coreutils}/bin/install -d -m 0755 "$agentDir"
          if [ -z "''${DRY_RUN_CMD:-}" ]; then
            input=/dev/null
            count=1
            if [ -e "$agentDir/settings.json" ]; then
              input="$agentDir/settings.json"
              count=2
            fi
            tmp=$(${pkgs.coreutils}/bin/mktemp "$agentDir/.settings.XXXXXX")
            trap '${pkgs.coreutils}/bin/rm -f "$tmp"' EXIT
            ${pkgs.jq}/bin/jq -s --argjson count "$count" -f ${./merge-settings.jq} ${settings} "$input" > "$tmp"
            ${pkgs.coreutils}/bin/chmod 0600 "$tmp"
            ${pkgs.coreutils}/bin/mv "$tmp" "$agentDir/settings.json"
          fi
        )
      ''
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
    ) (lib.filterAttrs (_: plugin: plugin ? source) resources.plugins)
    // lib.mapAttrs' (
      name: source:
      lib.nameValuePair ".agents/skills/${name}" {
        source = lib.mkDefault source;
        enable = cfg.skills.${name}.enable;
      }
    ) resources.skills;
  };
}
