# nix-instantiate --eval --strict tests/desktop-theme.nix \
#   --arg nixpkgs /path/to/nixpkgs --arg homeManager /path/to/home-manager
{
  nixpkgs,
  homeManager,
  system ? builtins.currentSystem,
}:
let
  t = import ./lib.nix { inherit nixpkgs homeManager system; };
  inherit (t) pkgs lib;

  cursorPackage = pkgs.writeTextDir "share/icons/Custom-Cursors/cursors/left_ptr" "";
  otherCursorPackage = pkgs.writeTextDir "share/icons/Adwaita/cursors/left_ptr" "";

  baseCfg = t.cfgFor [ ];
  base = t.hm baseCfg "test";

  enabledCfg = t.cfgFor [
    { modules.desktop-theme.enable = true; }
    { home-manager.users.test.home.pointerCursor.package = cursorPackage; }
  ];
  enabled = t.hm enabledCfg "test";

  overridden = t.hmFor [
    { modules.desktop-theme.enable = true; }
    {
      home-manager.users.test = {
        home.pointerCursor = {
          package = otherCursorPackage;
          name = "Adwaita";
          size = 24;
        };
        gtk = {
          theme = {
            name = "Adwaita";
            package = pkgs.adwaita-icon-theme;
          };
          iconTheme = {
            name = "Adwaita";
            package = pkgs.adwaita-icon-theme;
          };
          colorScheme = "light";
        };
        qt.platformTheme.name = "gtk3";
      };
    }
  ];

  multiCfg = t.evalSystem {
    users = [
      "alice"
      "bob"
    ];
    modules = [
      { modules.desktop-theme.enable = true; }
      {
        home-manager.users = {
          alice.home.pointerCursor.package = cursorPackage;
          bob.home.pointerCursor.package = otherCursorPackage;
        };
      }
    ];
  };
  alice = t.hm multiCfg.config "alice";
  bob = t.hm multiCfg.config "bob";

  archive = pkgs.writeText "test-cursor.zip" "";
  publicCursor = t.hmFor [
    {
      modules.desktop-theme = {
        enable = true;
        cursor = archive;
      };
    }
  ];
  invalidArchive =
    builtins.tryEval
      (t.cfgFor [
        {
          modules.desktop-theme.cursor = "not-a-package";
        }
      ]).modules.desktop-theme.cursor;

  missingCursor = builtins.tryEval (
    builtins.deepSeq (t.hmFor [ { modules.desktop-theme.enable = true; } ]).home.pointerCursor.package
      true
  );
in
assert !baseCfg.modules.desktop-theme.enable;
assert !baseCfg.modules.fcitx5.enable;
assert !base.home.pointerCursor.enable;
assert !base.gtk.enable;
assert enabledCfg.modules.desktop-theme.enable && enabledCfg.modules.fcitx5.enable;
assert enabled.home.pointerCursor.enable;
assert enabled.home.pointerCursor.package == cursorPackage;
assert enabled.home.pointerCursor.name == "Custom-Cursors";
assert enabled.home.pointerCursor.size == 48;
assert enabled.home.pointerCursor.gtk.enable;
assert enabled.home.pointerCursor.x11.enable;
assert enabled.home.pointerCursor.hyprcursor.enable;
assert enabled.gtk.enable;
assert enabled.gtk.theme.name == "Adwaita-dark";
assert enabled.gtk.theme.package == pkgs.gnome-themes-extra;
assert enabled.gtk.iconTheme.name == "Papirus-Dark";
assert enabled.gtk.iconTheme.package == pkgs.papirus-icon-theme;
assert enabled.gtk.colorScheme == "dark";
assert enabled.qt.enable;
assert enabled.qt.platformTheme.name == "qt6ct";
assert enabled.home.sessionVariables.XMODIFIERS == "@im=fcitx";
assert enabled.home.sessionVariables.QT_IM_MODULE == "fcitx";
assert enabled.systemd.user.sessionVariables.XCURSOR_THEME == "Custom-Cursors";
assert enabled.systemd.user.sessionVariables.XCURSOR_SIZE == "48";
assert enabled.systemd.user.sessionVariables.HYPRCURSOR_THEME == "Custom-Cursors";
assert enabled.systemd.user.sessionVariables.HYPRCURSOR_SIZE == "48";
assert lib.all (line: lib.hasInfix line enabled.xdg.configFile."environment.d/10-cursor.conf".text)
  [
    "XCURSOR_THEME=Custom-Cursors"
    "XCURSOR_SIZE=48"
    "HYPRCURSOR_THEME=Custom-Cursors"
    "HYPRCURSOR_SIZE=48"
  ];
assert lib.hasInfix "xsetroot -xcf" enabled.home.file.".xprofile".text;
assert lib.hasInfix "Custom-Cursors/cursors/left_ptr" enabled.home.file.".xprofile".text;
assert overridden.home.pointerCursor.package == otherCursorPackage;
assert overridden.home.pointerCursor.name == "Adwaita";
assert overridden.home.pointerCursor.size == 24;
assert overridden.gtk.theme.name == "Adwaita";
assert overridden.gtk.iconTheme.name == "Adwaita";
assert overridden.gtk.colorScheme == "light";
assert overridden.qt.platformTheme.name == "gtk3";
assert alice.home.pointerCursor.package == cursorPackage;
assert alice.home.pointerCursor.name == "Custom-Cursors";
assert bob.home.pointerCursor.package == otherCursorPackage;
assert bob.home.pointerCursor.name == "Custom-Cursors";
assert publicCursor.home.pointerCursor.package == t.attopkgs.custom-cursors { cursor = archive; };
assert !invalidArchive.success;
assert !missingCursor.success;
true
