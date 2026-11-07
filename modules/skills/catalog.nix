# Agent skills shared by Pi and Claude Code: source and the agents each one works with.
# `source` is one path, or an attrset of paths per agent when the agents need different copies.
{
  pkgs,
  lib,
  attopkgs,
}:
let
  both = [
    "pi"
    "claude-code"
  ];
  inherit (import ./sources.nix { inherit pkgs; }) mattSkills vercelSkills ponytail;
  contextMode = "${attopkgs.context-mode}/lib/context-mode";
  # context-mode ships Pi copies that call its Pi tools and generic copies that call its MCP tools.
  contextModeSkill = name: {
    pi = "${contextMode}/pi/skills/${name}";
    claude-code = "${contextMode}/skills/${name}";
  };
in
{
  # Pi-only: needs Pi's mermaid_diagram tool.
  pi-mermaid-studio = {
    source = "${attopkgs.pi-mermaid-studio}/lib/pi-mermaid-studio/skills/mermaid";
    agents = [ "pi" ];
  };
  # Pi-only: installs further skills with npx outside Nix.
  find-skills = {
    source = "${vercelSkills}/skills/find-skills";
    agents = [ "pi" ];
  };
  grilling = {
    source = "${mattSkills}/skills/productivity/grilling";
    agents = both;
  };
  improve-codebase-architecture = {
    source = "${mattSkills}/skills/engineering/improve-codebase-architecture";
    agents = both;
  };
  # Pi-only: rewrites the context-mode install, which Nix keeps read-only.
  ctx-upgrade = {
    source = contextModeSkill "ctx-upgrade";
    agents = [ "pi" ];
  };
}
//
  lib.genAttrs
    [
      "ponytail"
      "ponytail-audit"
      "ponytail-debt"
      "ponytail-gain"
      "ponytail-help"
      "ponytail-review"
    ]
    (name: {
      source = "${ponytail}/skills/${name}";
      agents = both;
    })
//
  lib.genAttrs
    [
      "ctx-doctor"
      "ctx-stats"
    ]
    (name: {
      source = contextModeSkill name;
      agents = both;
    })
