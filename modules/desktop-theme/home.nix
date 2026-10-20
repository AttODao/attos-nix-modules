{
  osConfig,
  options,
  config,
  lib,
  pkgs,
  attopkgs,
  ...
}:
let
  cfg = osConfig.modules.desktop-theme;
  cursor = config.home.pointerCursor;
  cursorSize = toString cursor.size;
  cursorEnvironment = {
    XCURSOR_THEME = cursor.name;
    XCURSOR_SIZE = cursorSize;
    HYPRCURSOR_THEME = cursor.name;
    HYPRCURSOR_SIZE = cursorSize;
  };
  inputEnvironment = {
    XMODIFIERS = "@im=fcitx";
    QT_IM_MODULE = "fcitx";
    SDL_IM_MODULE = "fcitx";
  };
  waylandEnvironment = {
    QT_QPA_PLATFORM = "wayland;xcb";
    MOZ_ENABLE_WAYLAND = "1";
  };
in
{
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.cursor != null || options.home.pointerCursor.package.isDefined;
        message = "desktop-theme: supply modules.desktop-theme.cursor or home.pointerCursor.package for every HM user.";
      }
    ];

    home.pointerCursor = {
      enable = true;
      package = lib.mkIf (cfg.cursor != null) (
        lib.mkDefault (attopkgs.custom-cursors { cursor = cfg.cursor; })
      );
      name = lib.mkDefault cfg.cursorName;
      size = lib.mkDefault cfg.cursorSize;
      gtk.enable = true;
      x11.enable = true;
      hyprcursor.enable = true;
    };

    gtk = {
      enable = true;
      theme = {
        name = lib.mkDefault "Adwaita-dark";
        package = lib.mkDefault pkgs.gnome-themes-extra;
      };
      iconTheme = {
        name = lib.mkDefault "Papirus-Dark";
        package = lib.mkDefault pkgs.papirus-icon-theme;
      };
      colorScheme = lib.mkDefault "dark";
    };

    # The old qt6ct dependency was package-only; use HM's native Qt plugin wiring.
    qt = {
      enable = true;
      platformTheme = {
        name = lib.mkDefault "qt6ct";
        package = lib.mkDefault pkgs.qt6Packages.qt6ct;
      };
    };

    home.sessionVariables = lib.mapAttrs (_: lib.mkDefault) (inputEnvironment // waylandEnvironment);

    systemd.user.sessionVariables = lib.mapAttrs (_: lib.mkDefault) (
      inputEnvironment
      // waylandEnvironment
      // cursorEnvironment
      // {
        QT_AUTO_SCREEN_FACTOR = "1";
      }
    );
  };
}
