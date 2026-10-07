{ config, lib, ... }:
{
  imports = [ ../fcitx5 ];

  options.modules.desktop-theme = {
    enable = lib.mkEnableOption "shared desktop theme configuration";
    cursorName = lib.mkOption {
      type = lib.types.str;
      default = "Custom-Cursors";
      description = "Cursor theme name for GTK, Xresources, Hyprcursor and session environment; must exist in the supplied cursor package.";
    };
    cursorSize = lib.mkOption {
      type = lib.types.ints.positive;
      default = 48;
      description = "Cursor size shared by GTK, Xresources, Hyprcursor and session environment.";
    };
    cursor = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = "Consumer-supplied cursor archive, built as Custom-Cursors for all HM users; null requires a per-user home.pointerCursor.package.";
    };
  };

  config = lib.mkIf config.modules.desktop-theme.enable {
    modules.fcitx5.enable = true;
    home-manager.sharedModules = [ ./home.nix ];
  };
}
