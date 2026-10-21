{ config, lib, ... }:
{
  options.modules.strata-desktop.enable = lib.mkEnableOption "shared Strata desktop configuration";

  config = lib.mkIf config.modules.strata-desktop.enable {
    home-manager.sharedModules = [ ./home.nix ];
  };
}
