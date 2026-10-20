{ config, lib, ... }:
{
  imports = [ ../foot ];

  options.modules.yazi.enable = lib.mkEnableOption "shared Yazi configuration";

  config = lib.mkIf config.modules.yazi.enable {
    modules.foot.enable = true;
    home-manager.sharedModules = [ ./home.nix ];
  };
}
