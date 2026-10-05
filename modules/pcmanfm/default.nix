{ config, lib, ... }:
{
  options.modules.pcmanfm.enable = lib.mkEnableOption "shared PCManFM configuration";

  config = lib.mkIf config.modules.pcmanfm.enable {
    home-manager.sharedModules = [ ./home.nix ];
  };
}
