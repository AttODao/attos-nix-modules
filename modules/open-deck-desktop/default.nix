{ config, lib, ... }:
let
  cfg = config.modules.open-deck-desktop;
in
{
  options.modules.open-deck-desktop = {
    enable = lib.mkEnableOption "shared Open-Deck Desktop configuration";
    binfmt = lib.mkEnableOption "`programs.appimage` with binfmt so other AppImages run directly (Open-Deck itself is wrapped with appimageTools and does not need it)";
  };

  config = lib.mkIf cfg.enable {
    programs.appimage = lib.mkIf cfg.binfmt {
      enable = true;
      binfmt = lib.mkDefault true;
    };
    home-manager.sharedModules = [ ./home.nix ];
  };
}
