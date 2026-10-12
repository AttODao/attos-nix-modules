# nix-instantiate --eval --strict --read-write-mode tests/pi.nix \
#   --arg nixpkgs /path/to/nixpkgs --arg homeManager /path/to/home-manager
{
  nixpkgs,
  homeManager,
  system ? builtins.currentSystem,
}:
let
  t = import ./lib.nix {
    inherit nixpkgs homeManager system;
    nixpkgsConfig.allowUnfreePredicate =
      pkg: (import "${toString nixpkgs}/lib").getName pkg == "context-mode";
  };
  inherit (t) pkgs lib;
  base = t.hmFor [ ];
  cfg = t.hmFor [ { modules.pi.enable = true; } ];
  dir = cfg.programs.pi-coding-agent.configDir;
  resources = import ../modules/pi/resources.nix {
    inherit pkgs lib;
    inherit (t) attopkgs;
  };
  pluginFor =
    home: name: home.home.file."${home.programs.pi-coding-agent.configDir}/extensions/${name}";
  allOff = t.hmFor [
    {
      modules.pi = {
        enable = true;
        plugins = lib.mapAttrs (_: _: { enable = false; }) resources.plugins;
        skills = lib.mapAttrs (_: _: { enable = false; }) resources.skills;
      };
    }
  ];
  selective = t.hmFor [
    {
      modules.pi = {
        enable = true;
        plugins.ponytail.enable = false;
        plugins.pi-mermaid-studio.enable = false;
        skills.ponytail-review.enable = false;
      };
    }
  ];
  invalidSwitch =
    builtins.tryEval
      (t.cfgFor [ { modules.pi.plugins.pi-usage.enable = "yes"; } ]).modules.pi.plugins.pi-usage.enable;
  relocated = t.hmFor [
    { modules.pi.enable = true; }
    {
      home-manager.users.test.programs.pi-coding-agent = {
        configDir = "/home/test/custom-pi";
        settings.extensions = [ "/home/test/custom-extension.ts" ];
      };
    }
  ];
  invalid = builtins.tryEval (t.cfgFor [ { modules.pi.enable = "yes"; } ]).modules.pi.enable;
  extensions = [
    {
      name = "pi-review";
      version = "0.2.17";
      entry = "./extensions/index.ts";
    }
    {
      name = "pi-usage";
      version = "0.2.0";
      entry = "./index.ts";
    }
    {
      name = "pi-keep-going";
      version = "1.1.0";
      entry = "./src/index.ts";
    }
  ];
in
assert !base.programs.pi-coding-agent.enable;
assert cfg.programs.pi-coding-agent.enable;
assert cfg.home.file."${dir}/settings.json".enable;
assert !(cfg.home.activation ? mergePiSettings);
assert cfg.programs.pi-coding-agent.package.version == "1.0.2";
assert
  cfg.programs.pi-coding-agent.settings.defaultTools == [
    "read"
    "grep"
    "find"
    "ls"
    "bash"
    "edit"
    "write"
    "codemode"
    "mermaid_diagram"
  ];
assert cfg.programs.pi-coding-agent.settings.sessions.autoTitle.refreshTurns == 4;
assert cfg.programs.pi-coding-agent.settings.packages == [ ];
assert lib.all (
  name:
  let
    file = pluginFor cfg name;
    manifest = builtins.fromJSON (builtins.unsafeDiscardStringContext file.source.text);
    plugin = resources.plugins.${name};
  in
  file.enable
  && manifest.pi.extensions == [ "${plugin.source}/${plugin.entry}" ]
  && manifest.pi.skills == [ ]
  && !(base.home.file ? "${dir}/extensions/${name}")
  && (pluginFor relocated name).source == file.source
  && !(pluginFor allOff name).enable
) (builtins.attrNames resources.plugins);
assert lib.all (name: !allOff.home.file.".agents/skills/${name}".enable) (
  builtins.attrNames resources.skills
);
assert !(pluginFor selective "pi-mermaid-studio").enable;
assert selective.home.file.".agents/skills/pi-mermaid-studio".enable;
assert !(lib.elem "mermaid_diagram" selective.programs.pi-coding-agent.settings.defaultTools);
assert !(pluginFor selective "ponytail").enable;
assert selective.home.file.".agents/skills/ponytail".enable;
assert !selective.home.file.".agents/skills/ponytail-review".enable;
assert !invalidSwitch.success;
assert lib.elem pkgs.tmux cfg.programs.pi-coding-agent.extraPackages;
assert lib.elem pkgs.bun cfg.programs.pi-coding-agent.extraPackages;
assert lib.elem pkgs.git cfg.programs.pi-coding-agent.extraPackages;
assert lib.all (
  extension:
  let
    plugin = resources.plugins.${extension.name};
    manifest = builtins.fromJSON (builtins.readFile (plugin.source + "/package.json"));
  in
  manifest.version == extension.version
  && manifest.pi.extensions == [ extension.entry ]
  && (manifest.dependencies or { }) == { }
  && builtins.pathExists (plugin.source + "/${extension.entry}")
) extensions;
assert
  resources.plugins.pi-mermaid-studio.source
  == "${t.attopkgs.pi-mermaid-studio}/lib/pi-mermaid-studio";
assert
  cfg.home.file.".agents/skills/pi-mermaid-studio".source
  == "${t.attopkgs.pi-mermaid-studio}/lib/pi-mermaid-studio/skills/mermaid";
assert cfg.home.file.".agents/skills/pi-mermaid-studio".enable;
assert !(lib.elem "mermaid_diagram" allOff.programs.pi-coding-agent.settings.defaultTools);
assert t.attopkgs.pi-mermaid-studio.version == "0.2.1";
assert t.attopkgs.pi-mermaid-studio.drvPath != "";
assert lib.hasInfix "ExitOnForwardFailure=yes" cfg.home.file."${dir}/AGENTS.md".text;
assert lib.hasInfix "37421 is" cfg.home.file."${dir}/AGENTS.md".text;
assert selective.home.file."${dir}/AGENTS.md".text == builtins.readFile ../modules/pi/AGENTS.md;
assert allOff.home.file."${dir}/AGENTS.md".text == selective.home.file."${dir}/AGENTS.md".text;
assert !(lib.hasInfix "Mermaid Studio" selective.home.file."${dir}/AGENTS.md".text);
assert cfg.home.file."${dir}/AGENTS.md".enable;
assert lib.hasInfix "use context-mode" cfg.home.file."${dir}/AGENTS.md".text;
assert lib.hasInfix "session_search" cfg.home.file."${dir}/AGENTS.md".text;
assert
  relocated.home.file."/home/test/custom-pi/AGENTS.md".text == cfg.home.file."${dir}/AGENTS.md".text;
assert (pluginFor cfg "pi-sessions").enable;
assert (pluginFor cfg "ponytail").enable;
assert !(cfg.home.file ? "${dir}/skills/ponytail");
assert lib.all (
  name:
  cfg.home.file.".agents/skills/${name}".enable
  && lib.hasInfix "name: ${name}" (
    builtins.readFile (cfg.home.file.".agents/skills/${name}".source + "/SKILL.md")
  )
) (builtins.filter (name: name != "pi-mermaid-studio") (builtins.attrNames resources.skills));
assert lib.hasInfix "# HTML Report Format" (
  builtins.readFile (
    cfg.home.file.".agents/skills/improve-codebase-architecture".source + "/HTML-REPORT.md"
  )
);
assert !(cfg.home.file ? "${dir}/auth.json");
assert (pluginFor relocated "pi-sessions").enable;
assert relocated.home.sessionVariables.PI_CODING_AGENT_DIR == "/home/test/custom-pi";
assert
  relocated.programs.pi-coding-agent.settings.extensions == [ "/home/test/custom-extension.ts" ];
assert !invalid.success;
true
