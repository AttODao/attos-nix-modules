{ config, lib, ... }:
{
  options.modules.open-deck-desktop = {
    enable = lib.mkEnableOption "shared Open-Deck Desktop configuration (requires NixOS AppImage support)";
    binfmt = lib.mkEnableOption "system-wide AppImage execution through binfmt";
  };

  config = lib.mkIf config.modules.open-deck-desktop.enable {
    programs.appimage = {
      enable = true;
      binfmt = lib.mkDefault config.modules.open-deck-desktop.binfmt;
    };
    home-manager.sharedModules = [ ./home.nix ];
  };
}
