{ config, lib, ... }:
{
  options.modules.pi.enable = lib.mkEnableOption "shared Pi configuration";

  config = lib.mkIf config.modules.pi.enable {
    home-manager.sharedModules = [ ./home.nix ];
  };
}
