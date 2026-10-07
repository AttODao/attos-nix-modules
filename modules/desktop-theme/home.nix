{
  osConfig,
  config,
  lib,
  pkgs,
  ...
}:
let
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
in
{
  config = lib.mkIf osConfig.modules.desktop-theme.enable {
    home.pointerCursor = {
      enable = true;
      # Supply the package per HM user; the archive URL/hash stays with the consumer.
      package = lib.mkDefault (
        throw "desktop-theme: set home.pointerCursor.package for every HM user (for example attopkgs.custom-cursors { cursor = pkgs.fetchurl { ... }; })."
      );
      name = lib.mkDefault "Custom-Cursors";
      size = lib.mkDefault 48;
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

    home.sessionVariables = lib.mapAttrs (_: lib.mkDefault) inputEnvironment;

    systemd.user.sessionVariables = lib.mapAttrs (_: lib.mkDefault) (
      inputEnvironment
      // cursorEnvironment
      // {
        QT_QPA_PLATFORM = "wayland;xcb";
        QT_AUTO_SCREEN_FACTOR = "1";
        MOZ_ENABLE_WAYLAND = "1";
      }
    );

    xdg.configFile."environment.d/10-cursor.conf".text = lib.mkDefault (
      lib.concatStringsSep "\n" (lib.mapAttrsToList (name: value: "${name}=${value}") cursorEnvironment)
      + "\n"
    );

    # Retain the X login path without enabling a separate HM-managed X session.
    home.file.".xprofile".text = lib.mkDefault ''
      ${lib.concatStringsSep "\n" (
        lib.mapAttrsToList (name: value: "export ${name}=${lib.escapeShellArg value}") (
          inputEnvironment // cursorEnvironment
        )
      )}

      if [ -r "$HOME/.Xresources" ]; then
        ${pkgs.xrdb}/bin/xrdb -merge "$HOME/.Xresources"
      fi

      ${pkgs.xsetroot}/bin/xsetroot -xcf ${lib.escapeShellArg "${cursor.package}/share/icons/${cursor.name}/cursors/left_ptr"} ${lib.escapeShellArg cursorSize}
    '';
  };
}
