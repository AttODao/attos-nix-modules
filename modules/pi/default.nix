{
  config,
  lib,
  pkgs,
  attopkgs,
  ...
}:
let
  resources = import ./resources.nix { inherit pkgs attopkgs; };
in
{
  imports = [ ../skills ];

  options.modules.pi = {
    enable = lib.mkEnableOption "shared Pi configuration";
    plugins = lib.mapAttrs (name: _: {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Install the bundled Pi plugin ${name} (catalog in `modules/pi/resources.nix`).";
      };
    }) resources.plugins;
  };

  config = lib.mkIf config.modules.pi.enable {
    modules.skills.enable = true;
    home-manager.sharedModules = [ ./home.nix ];
  };
}
