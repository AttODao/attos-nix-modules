# nix-instantiate --eval --strict --read-write-mode tests/claude-code.nix \
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
      pkg:
      builtins.elem ((import "${toString nixpkgs}/lib").getName pkg) [
        "claude-code"
        "context-mode"
      ];
  };
  inherit (t) pkgs lib;
  base = t.cfgFor [ ];
  cfg = t.hmFor [ { modules.claude-code.enable = true; } ];
  dir = cfg.programs.claude-code.configDir;
  resources = import ../modules/pi/resources.nix {
    inherit pkgs lib;
    inherit (t) attopkgs;
  };
  names = builtins.attrNames base.modules.claude-code.skills;
  skillFile = home: name: home.home.file."${dir}/skills/${name}";
  selective = t.hmFor [
    {
      modules.claude-code = {
        enable = true;
        skills.ponytail-review.enable = false;
        contextMode.enable = false;
      };
    }
  ];
  overridden = t.hmFor [
    { modules.claude-code.enable = true; }
    { home-manager.users.test.programs.claude-code.skills.grilling = "custom"; }
  ];
  invalid =
    builtins.tryEval
      (t.cfgFor [ { modules.claude-code.skills.grilling.enable = "yes"; } ])
      .modules.claude-code.skills.grilling.enable;
in
assert !base.modules.claude-code.enable;
assert !base.home-manager.users.test.programs.claude-code.enable;
assert cfg.programs.claude-code.enable;
assert builtins.elem cfg.programs.claude-code.finalPackage cfg.home.packages;
assert cfg.programs.claude-code.package == t.attopkgs.claude-code;
assert t.attopkgs.claude-code.version == "2.1.302";
assert lib.versionAtLeast cfg.programs.claude-code.package.version "2.1.157";
# 認証・settingsの手編集を保持する。
assert !(cfg.home.file ? "${dir}/settings.json");
assert !(cfg.home.file ? "${dir}/.credentials.json");
assert !(names == [ ]) && lib.all (name: resources.skills ? ${name}) names;
assert !(base.modules.claude-code.skills ? pi-mermaid-studio);
assert !(base.modules.claude-code.skills ? ctx-upgrade);
assert lib.all (
  name:
  cfg.programs.claude-code.skills.${name} == resources.skills.${name} && skillFile cfg name ? source
) names;
assert lib.hasInfix "name: grilling" (builtins.readFile (resources.skills.grilling + "/SKILL.md"));
assert
  cfg.programs.claude-code.mcpServers.context-mode.command
  == "${t.attopkgs.context-mode}/bin/context-mode";
assert builtins.elem t.attopkgs.context-mode cfg.home.packages;
assert cfg.home.file ? "${dir}/skills/claude-code-home-manager";
assert !(selective.programs.claude-code.skills ? ponytail-review);
assert selective.programs.claude-code.skills ? ponytail;
assert selective.programs.claude-code.mcpServers == { };
assert !(builtins.elem t.attopkgs.context-mode selective.home.packages);
assert !(selective.home.file ? "${dir}/skills/claude-code-home-manager");
assert overridden.programs.claude-code.skills.grilling == "custom";
assert !invalid.success;
true
