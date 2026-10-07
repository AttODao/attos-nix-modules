# Host-shaped integration fixtures for .dotfiles 68c1ab0 (not hardware or deployment tests).
# nix-instantiate --eval --strict --read-write-mode tests/desktop-hosts.nix \
#   --arg nixpkgs /path/to/nixpkgs --arg homeManager /path/to/home-manager
{
  nixpkgs,
  homeManager,
  system ? builtins.currentSystem,
}:
let
  t = import ./lib.nix {
    inherit nixpkgs homeManager system;
    nixpkgsConfig.allowUnfree = true;
  };
  inherit (t) pkgs lib;
  cursor = pkgs.fetchurl {
    name = "desktop-test-cursor.zip";
    url = "https://example.invalid/cursor.zip";
    hash = lib.fakeHash;
  };
  desktopMonitors = [
    {
      output = "HDMI-A-2";
      mode = "1920x1080@100";
      position = "0x0";
      bitdepth = 10;
      cm = "hdr";
    }
    {
      output = "DP-1";
      mode = "2560x1440@143.999";
      position = "1920x260";
      bitdepth = 10;
      cm = "hdr";
    }
    {
      output = "HDMI-A-1";
      mode = "1920x1080@60";
      position = "4480x394";
    }
  ];
  common = {
    users.users.attodao.shell = pkgs.zsh;
    home-manager.users.attodao.home.stateVersion = "26.05";
    home-manager.users.attodao.programs.noctalia.settings.calendar.account.personal = {
      type = "caldav";
      server_url = "https://mail.example.org/radicale/";
      username = "user@example.org";
      credential_source = "file";
      password_file = "/run/secrets/calendar-password";
    };
    modules = {
      greeter = {
        enable = true;
        inherit cursor;
      };
      login-pin.enable = true;
      pipewire.enable = true;
      discord.enable = true;
      floorp.enable = true;
      thunderbird.enable = true;
      vscode.enable = true;
      open-deck-desktop.enable = true;
      pi.enable = true;
      zsh.enable = true;
      ssh.enable = true;
      noctalia = {
        screenRecorder.enable = true;
        dock.pinned = [
          "footclient"
          "pcmanfm"
          "code"
          "floorp"
          "thunderbird"
        ];
      };
    };
  };
  attodesk =
    (t.evalSystem {
      users = [ "attodao" ];
      modules = [
        common
        {
          networking.hostName = "attodesk";
          modules = {
            hyprland.monitors = desktopMonitors;
            greeter.output = "DP-1";
            userDirs.dataDirectory = "/mnt/hdd1";
            solaar.enable = true;
            pipeasio.enable = true;
            linux-wallpaperengine.enable = true;
            pandora-launcher.enable = true;
            opencloud-client.enable = true;
          };
          programs.steam.enable = true;
          # GPU and recorder choices remain ordinary consumer settings.
          home-manager.users.attodao.programs.noctalia.settings.plugin_settings."noctalia/screen_recorder" = {
            video_source = "focused";
            video_codec = "hevc_hdr";
          };
        }
      ];
    }).config;
  attolap =
    (t.evalSystem {
      users = [ "attodao" ];
      modules = [
        common
        {
          networking.hostName = "attolap";
          modules.hyprland = {
            lidSwitch.enable = true;
            neowall.enable = true;
          };
          home-manager.users.attodao = {
            # User overrides must replace one default without losing the other directories.
            xdg.userDirs.videos = "/home/attodao/My Videos";
            programs.foot.settings.main.font = "monospace:size=13";
            programs.noctalia.settings.plugin_settings."noctalia/screen_recorder" = {
              video_source = "portal";
              video_codec = "h264";
            };
            home.file."Pictures/Screenshots/.keep".text = "";
          };
        }
      ];
    }).config;
  deskHome = t.hm attodesk "attodao";
  lapHome = t.hm attolap "attodao";
  portable =
    (t.evalSystem {
      users = [ "operator" ];
      modules = [
        {
          modules.hyprland.enable = true;
          users.users.operator.home = "/srv/operator";
        }
      ];
    }).config;
  portableHome = t.hm portable "operator";
  alternateGreeter = t.cfgFor [
    {
      modules.greeter = {
        enable = true;
        inherit cursor;
        output = "DP-1";
      };
      services.displayManager.noctalia-greeter.settings = {
        user.default = "test";
        session.default = "Test Session";
        cursor = {
          theme = "Adwaita";
          size = 24;
          path = "/run/current-system/sw/share/icons";
        };
        output.name = "HDMI-A-1";
      };
    }
  ];
  greeterSettings = alternateGreeter.services.displayManager.noctalia-greeter.settings;
  defaultMonitor = [
    {
      output = "";
      mode = "preferred";
      position = "auto";
      scale = 1;
    }
  ];
  luaConfig = home: home.xdg.configFile."hypr/hyprland.lua".text;
in
assert attodesk.modules.hyprland.enable && attolap.modules.hyprland.enable;
assert attodesk.modules.fcitx5.enable && attolap.modules.fcitx5.enable;
assert attodesk.modules.fonts.enable && attolap.modules.fonts.enable;
assert attodesk.services.pipewire.enable && attolap.services.pipewire.enable;
assert attodesk.programs.hyprland.withUWSM && attolap.programs.hyprland.withUWSM;
assert attodesk.services.displayManager.noctalia-greeter.settings.output.name == "DP-1";
assert !(attolap.services.displayManager.noctalia-greeter.settings ? output);
assert greeterSettings.user.default == "test" && greeterSettings.session.default == "Test Session";
assert
  greeterSettings.cursor == {
    theme = "Adwaita";
    size = 24;
    path = "/run/current-system/sw/share/icons";
  };
assert greeterSettings.output.name == "HDMI-A-1";
assert
  deskHome.wayland.windowManager.hyprland.settings.monitor
  == map (monitor: monitor // { scale = 1; }) desktopMonitors;
assert lapHome.wayland.windowManager.hyprland.settings.monitor == defaultMonitor;
assert !lib.hasInfix "switch:on:Lid Switch" (luaConfig deskHome);
assert lib.hasInfix "switch:on:Lid Switch" (luaConfig lapHome);
assert !lib.hasInfix "neowall" (luaConfig deskHome);
assert lib.hasInfix "neowall" (luaConfig lapHome);
assert deskHome.xdg.userDirs.desktop == "/home/attodao/Desktop";
assert deskHome.xdg.userDirs.pictures == "/mnt/hdd1/Pictures";
assert deskHome.xdg.userDirs.videos == "/mnt/hdd1/Videos";
assert lapHome.xdg.userDirs.pictures == "/home/attodao/Pictures";
assert lapHome.xdg.userDirs.videos == "/home/attodao/My Videos";
assert lib.hasInfix "/mnt/hdd1/Pictures/Screenshots" (luaConfig deskHome);
assert lib.hasInfix "/home/attodao/Pictures/Screenshots" (luaConfig lapHome);
assert
  deskHome.programs.noctalia.settings.plugin_settings."noctalia/screen_recorder".directory
  == "/mnt/hdd1/Videos/Recordings";
assert
  lapHome.programs.noctalia.settings.plugin_settings."noctalia/screen_recorder".directory
  == "/home/attodao/My Videos/Recordings";
assert
  deskHome.programs.noctalia.settings.plugin_settings."noctalia/screen_recorder".video_codec
  == "hevc_hdr";
assert
  lapHome.programs.noctalia.settings.plugin_settings."noctalia/screen_recorder".video_codec == "h264";
assert deskHome.programs.foot.settings.main.font == "Inconsolata Nerd Font Mono:size=11";
assert lapHome.programs.foot.settings.main.font == "monospace:size=13";
assert attodesk.modules.solaar.enable && !attolap.modules.solaar.enable;
assert attodesk.modules.pipeasio.enable && !attolap.modules.pipeasio.enable;
assert
  attodesk.modules.linux-wallpaperengine.enable && !attolap.modules.linux-wallpaperengine.enable;
assert attodesk.modules.pandora-launcher.enable && !attolap.modules.pandora-launcher.enable;
assert attodesk.modules.opencloud-client.enable && !attolap.modules.opencloud-client.enable;
assert attodesk.programs.steam.enable && !attolap.programs.steam.enable;
assert !(lapHome.systemd.user.services ? solaar);
assert !(lapHome.systemd.user.services ? opencloud);
assert deskHome.home.stateVersion == "26.05" && lapHome.home.stateVersion == "26.05";
assert portableHome.home.homeDirectory == "/srv/operator";
assert portableHome.xdg.userDirs.pictures == "/srv/operator/Pictures";
assert lib.hasInfix "/srv/operator/Pictures/Screenshots" (luaConfig portableHome);
assert !(portable.home-manager.users ? attodao);
assert !portable.modules.greeter.enable && !portable.modules.login-pin.enable;
assert !portable.modules.solaar.enable && !portable.modules.pipeasio.enable;
assert !portable.modules.docker.enable && portable.modules.public-services == { };
assert attodesk.system.build.toplevel.drvPath != "" && attolap.system.build.toplevel.drvPath != "";
assert
  deskHome.home.activationPackage.drvPath != "" && lapHome.home.activationPackage.drvPath != "";
true
