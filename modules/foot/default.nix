{ config, lib, ... }:
{
  imports = [ ../fonts ];

  options.modules.foot.enable = lib.mkEnableOption "shared Foot configuration";

  config = lib.mkIf config.modules.foot.enable {
    modules.fonts.enable = true;
    home-manager.sharedModules = [ ./home.nix ];
  };
}
