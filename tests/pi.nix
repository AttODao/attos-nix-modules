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
  skills = [
    "find-skills"
    "grilling"
    "improve-codebase-architecture"
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
  ];
assert cfg.programs.pi-coding-agent.settings.sessions.autoTitle.refreshTurns == 4;
assert builtins.length cfg.programs.pi-coding-agent.settings.packages == 1;
assert lib.hasInfix "context-mode-1.0.169" (
  builtins.head cfg.programs.pi-coding-agent.settings.packages
);
assert lib.elem pkgs.tmux cfg.programs.pi-coding-agent.extraPackages;
assert lib.elem pkgs.bun cfg.programs.pi-coding-agent.extraPackages;
assert lib.elem pkgs.git cfg.programs.pi-coding-agent.extraPackages;
assert lib.all (
  extension:
  let
    file = cfg.home.file."${dir}/extensions/${extension.name}";
    manifest = builtins.fromJSON (builtins.readFile (file.source + "/package.json"));
  in
  file.enable
  && manifest.version == extension.version
  && manifest.pi.extensions == [ extension.entry ]
  && (manifest.dependencies or { }) == { }
  && builtins.pathExists (file.source + "/${extension.entry}")
  && !(base.home.file ? "${dir}/extensions/${extension.name}")
  && relocated.home.file."/home/test/custom-pi/extensions/${extension.name}".source == file.source
) extensions;
assert cfg.home.file."${dir}/extensions/pi-sessions".enable;
assert cfg.home.file."${dir}/extensions/ponytail".enable;
assert !(cfg.home.file ? "${dir}/skills/ponytail");
assert lib.all (
  name:
  cfg.home.file.".agents/skills/${name}".enable
  && lib.hasInfix "name: ${name}" (
    builtins.readFile (cfg.home.file.".agents/skills/${name}".source + "/SKILL.md")
  )
) skills;
assert lib.hasInfix "# HTML Report Format" (
  builtins.readFile (
    cfg.home.file.".agents/skills/improve-codebase-architecture".source + "/HTML-REPORT.md"
  )
);
assert !(cfg.home.file ? "${dir}/auth.json");
assert relocated.home.file."/home/test/custom-pi/extensions/pi-sessions".enable;
assert relocated.home.sessionVariables.PI_CODING_AGENT_DIR == "/home/test/custom-pi";
assert
  relocated.programs.pi-coding-agent.settings.extensions == [ "/home/test/custom-extension.ts" ];
assert !invalid.success;
true
