{ config, lib, ... }:
{
  options.modules.floorp.enable = lib.mkEnableOption "shared Floorp configuration";

  config = lib.mkIf config.modules.floorp.enable {
    home-manager.sharedModules = [ ./home.nix ];
  };
}
