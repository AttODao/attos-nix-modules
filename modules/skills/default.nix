{
  config,
  lib,
  pkgs,
  attopkgs,
  ...
}:
let
  catalog = import ./catalog.nix { inherit pkgs lib attopkgs; };
in
{
  options.modules.skills = {
    enable = lib.mkEnableOption "shared agent skills for Pi and Claude Code";
  }
  // lib.mapAttrs (name: skill: {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install the shared skill ${name} for ${lib.concatStringsSep " and " skill.agents} when those agents are enabled.";
    };
  }) catalog;

  config = lib.mkIf config.modules.skills.enable {
    home-manager.sharedModules = [ ./home.nix ];
  };
}
