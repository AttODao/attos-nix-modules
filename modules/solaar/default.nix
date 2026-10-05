{ config, lib, ... }:
{
  imports = [
    ./nixos.nix
    ../noctalia
  ];

  options.modules.solaar.enable = lib.mkEnableOption "shared Solaar configuration with Kando";

  config = lib.mkIf config.modules.solaar.enable {
    modules.noctalia.enable = true;
    home-manager.sharedModules = [ ./home.nix ];
  };
}
