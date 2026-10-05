# nix-instantiate --eval --strict tests/hyprland.nix \
#   --arg nixpkgs /path/to/nixpkgs --arg homeManager /path/to/home-manager
{
  nixpkgs,
  homeManager,
  system ? builtins.currentSystem,
}:
let
  t = import ./lib.nix { inherit nixpkgs homeManager system; };
  inherit (t) pkgs lib;
  cursorUrl = "https://example.invalid/cursor.zip";
  cursorArchive = pkgs.fetchurl {
    name = "custom-cursors.zip";
    url = cursorUrl;
    hash = lib.fakeHash;
  };
  cursorPackage = t.attopkgs.custom-cursors { cursor = cursorArchive; };
  desktopMonitors = [
    {
      output = "HDMI-A-2";
      mode = "1920x1080@100";
      position = "0x0";
      scale = 1;
      bitdepth = 10;
      cm = "hdr";
    }
    {
      output = "DP-1";
      mode = "2560x1440@143.999";
      position = "1920x260";
      scale = 1;
      bitdepth = 10;
      cm = "hdr";
    }
  ];
  desktopCfg = t.cfgFor [
    {
      modules.hyprland = {
        enable = true;
        monitors = desktopMonitors;
      };
      modules.greeter = {
        enable = true;
        output = "DP-1";
        cursor = cursorArchive;
      };
      modules.userDirs.enable = true;
    }
  ];
  desktop = t.hm desktopCfg "test";
  laptopCfg = t.cfgFor [
    {
      modules.hyprland = {
        enable = true;
        lidSwitch.enable = true;
        neowall.enable = true;
      };
      modules.greeter = {
        enable = true;
        cursor = cursorArchive;
      };
      modules.userDirs.enable = true;
    }
  ];
  laptop = t.hm laptopCfg "test";
  settings = cfg: cfg.wayland.windowManager.hyprland.settings;
  luaConfig = cfg: cfg.xdg.configFile."hypr/hyprland.lua".text;
  invalidMonitors = builtins.tryEval (
    builtins.deepSeq
      (settings (
        t.hmFor [
          {
            modules.hyprland = {
              enable = true;
              monitors = [ { scale = 0; } ];
            };
          }
        ]
      )).monitor
      true
  );
  invalidOutput =
    builtins.tryEval
      (t.cfgFor [ { modules.greeter.output = 1; } ]).modules.greeter.output;
  missingCursor =
    builtins.tryEval
      (t.cfgFor [ { modules.greeter.enable = true; } ])
      .services.displayManager.noctalia-greeter.settings.cursor.path;
  invalidCursor =
    builtins.tryEval
      (t.cfgFor [ { modules.greeter.cursor = cursorUrl; } ]).modules.greeter.cursor;
  invalidExtra =
    builtins.tryEval
      (t.cfgFor [ { modules.hyprland.extraConfig = ""; } ]).modules.hyprland.enable;
in
assert desktop.wayland.windowManager.hyprland.configType == "lua";
assert !desktop.wayland.windowManager.hyprland.systemd.enable;
assert (settings desktop).monitor == desktopMonitors;
assert
  (settings laptop).monitor == [
    {
      output = "";
      mode = "preferred";
      position = "auto";
      scale = 1;
    }
  ];
assert builtins.length (settings laptop).bind == builtins.length (settings desktop).bind + 2;
assert !lib.hasInfix "neowall" (luaConfig desktop);
assert lib.hasInfix "uwsm app -t service -- neowall" (luaConfig laptop);
assert lib.hasInfix "switch:on:Lid Switch" (luaConfig laptop);
assert lib.hasInfix "fcitx5-daemon.service" (luaConfig desktop);
assert lib.hasInfix "uwsm app -t service -- noctalia" (luaConfig desktop);
assert lib.hasInfix "/home/test/Pictures/Screenshots" (luaConfig desktop);
assert laptop.xdg.configFile."neowall/config.vibe".enable;
assert lib.elem pkgs.hyprshot desktop.home.packages;
assert lib.elem pkgs.neowall laptop.home.packages;
assert desktopCfg.programs.hyprland.enable && desktopCfg.programs.hyprland.withUWSM;
assert desktopCfg.programs.dconf.enable && desktopCfg.services.gvfs.enable;
assert desktopCfg.services.logind.settings.Login.HandlePowerKey == "ignore";
assert laptopCfg.services.logind.settings.Login.HandleLidSwitch == "ignore";
assert desktopCfg.services.displayManager.noctalia-greeter.settings.output.name == "DP-1";
assert !(laptopCfg.services.displayManager.noctalia-greeter.settings ? output);
assert
  desktopCfg.services.displayManager.noctalia-greeter.settings.session.default
  == "Hyprland (uwsm-managed)";
assert
  desktopCfg.services.displayManager.noctalia-greeter.settings.cursor.path
  == "${cursorPackage}/share/icons";
assert
  desktopCfg.services.displayManager.noctalia-greeter.settings.cursor.theme == "Custom-Cursors";
assert lib.hasInfix "Custom-Cursors" (luaConfig desktop);
assert cursorPackage.pname == "custom-cursors";
assert cursorPackage.src.name == "custom-cursors.zip";
assert cursorPackage.src.urls == [ cursorUrl ];
assert cursorPackage.src == cursorArchive;
assert cursorPackage.src.outputHash == lib.fakeHash;
assert desktop.home.activationPackage.drvPath != "" && laptop.home.activationPackage.drvPath != "";
assert
  desktopCfg.system.build.toplevel.drvPath != "" && laptopCfg.system.build.toplevel.drvPath != "";
assert !invalidMonitors.success && !invalidOutput.success && !invalidExtra.success;
assert !missingCursor.success && !invalidCursor.success;
true
