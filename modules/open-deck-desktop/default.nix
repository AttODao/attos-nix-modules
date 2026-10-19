{ config, lib, ... }:
let
  cfg = config.modules.open-deck-desktop;
in
{
  options.modules.open-deck-desktop = {
    enable = lib.mkEnableOption "shared Open-Deck Desktop configuration";
    binfmt = lib.mkEnableOption "system-wide AppImage execution through binfmt";
  };

  config = lib.mkIf cfg.enable {
    # The package is already wrapped with appimageTools; binfmt is only for other AppImages.
    programs.appimage = lib.mkIf cfg.binfmt {
      enable = true;
      binfmt = lib.mkDefault true;
    };
    home-manager.sharedModules = [ ./home.nix ];
  };
}
