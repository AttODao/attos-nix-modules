{ config, lib, ... }:
{
  options.modules.fcitx5.enable = lib.mkEnableOption "shared Fcitx5 with SKK configuration";

  config = lib.mkIf config.modules.fcitx5.enable {
    home-manager.sharedModules = [ ./home.nix ];
  };
}
