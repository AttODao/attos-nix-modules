{
  osConfig,
  lib,
  pkgs,
  attopkgs,
  ...
}:
let
  cfg = osConfig.modules.skills;
  catalog = import ./catalog.nix { inherit pkgs lib attopkgs; };
  for =
    agent: lib.filterAttrs (name: skill: cfg.${name}.enable && lib.elem agent skill.agents) catalog;
in
{
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      # Pi discovers skills in ~/.agents/skills.
      (lib.mkIf osConfig.modules.pi.enable {
        home.file = lib.mapAttrs' (
          name: skill: lib.nameValuePair ".agents/skills/${name}" { source = lib.mkDefault skill.source; }
        ) (for "pi");
      })
      (lib.mkIf osConfig.modules.claude-code.enable {
        programs.claude-code.skills = lib.mapAttrs (_: skill: lib.mkDefault skill.source) (
          for "claude-code"
        );
      })
    ]
  );
}
