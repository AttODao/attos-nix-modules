{ config, lib, ... }:
{
  imports = [ ./nixos.nix ];

  options.modules.fonts.enable = lib.mkEnableOption "shared user fonts";

  config = lib.mkIf config.modules.fonts.enable {
    home-manager.sharedModules = [ ./home.nix ];
  };
}
