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
  mattSkills = pkgs.fetchFromGitHub {
    owner = "mattpocock";
    repo = "skills";
    rev = "006a52be23e0178375e083e30535fa8224471f3e";
    hash = "sha256-g32DrgTt1/6MXeuHnlGAcl7xb+kema5+9UVsiTbgYIs=";
  };
  vercelSkills = pkgs.fetchFromGitHub {
    owner = "vercel-labs";
    repo = "skills";
    rev = "18f96ea131dab3b0fcc9b27cf7c6f6cbb6174680";
    hash = "sha256-FJLz/HfqBWtsJUuKs0w/OmErdyUi5/fKdNiTBpDtT1A=";
  };
  contextMode = attopkgs.context-mode;
  piSessions =
    if cfg.piSessionsSource != null then
      cfg.piSessionsSource
    else
      pkgs.fetchFromGitHub {
        owner = "thurstonsand";
        repo = "pi-sessions";
        rev = "3f7cd305414e95f9350541a5f95cd286a06e3705";
        hash = "sha256-abHSnNpD0tOXObRfLDJPpZPapm3+kvMaVWED+jEhMO4=";
      };
  ponytail = pkgs.fetchFromGitHub {
    owner = "DietrichGebert";
    repo = "ponytail";
    rev = "v4.10.3";
    hash = "sha256-aypYnQf+zkKGj+dfs+qFKTFIvaick9p0XJNtPkSwIB0=";
  };
in
{
  config = lib.mkIf osConfig.modules.pi.enable {
    programs.pi-coding-agent = {
      enable = true;
      package = attopkgs.pi;
      extraPackages = [
        pkgs.bun
        pkgs.tmux
        contextMode
      ];
      settings = {
        packages = [ "${contextMode}/lib/context-mode" ];
        defaultTools = [
          "read"
          "grep"
          "find"
          "ls"
          "bash"
          "edit"
          "write"
          "codemode"
        ];
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
            ${pkgs.jq}/bin/jq -s --argjson count "$count" 'if length == $count and all(.[]; type == "object") then reduce .[] as $settings ({}; . * $settings) else error("Pi settings must be one JSON object") end' ${settings} "$input" > "$tmp"
            ${pkgs.coreutils}/bin/chmod 0600 "$tmp"
            ${pkgs.coreutils}/bin/mv "$tmp" "$agentDir/settings.json"
          fi
        )
      ''
    );

    home.packages = [
      pkgs.tmux
      contextMode
    ];
    home.file = {
      "${agentDir}/settings.json".enable = lib.mkIf (cfg.settingsMode == "merge") false;
      "${agentDir}/extensions/pi-sessions".source = piSessions;
      # The package manifest loads Ponytail's skills too; do not register them twice.
      "${agentDir}/extensions/ponytail".source = ponytail;
      # Reuse Pi's shared skill discovery location to avoid duplicate local copies.
      ".agents/skills/find-skills".source = "${vercelSkills}/skills/find-skills";
      ".agents/skills/grilling".source = "${mattSkills}/skills/productivity/grilling";
      ".agents/skills/improve-codebase-architecture".source =
        "${mattSkills}/skills/engineering/improve-codebase-architecture";
    };
  };
}
