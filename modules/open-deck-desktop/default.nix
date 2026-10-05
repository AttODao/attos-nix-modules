{ config, lib, ... }:
{
  options.modules.open-deck-desktop.enable = lib.mkEnableOption "shared Open-Deck Desktop configuration (requires NixOS AppImage support)";

  config = lib.mkIf config.modules.open-deck-desktop.enable {
    programs.appimage.enable = true;
    home-manager.sharedModules = [ ./home.nix ];
  };
}
