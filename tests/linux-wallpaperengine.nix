# nix-instantiate --eval --strict tests/linux-wallpaperengine.nix \
#   --arg nixpkgs /path/to/nixpkgs --arg homeManager /path/to/home-manager
{
  nixpkgs,
  homeManager,
  system ? builtins.currentSystem,
}:
let
  t = import ./lib.nix { inherit nixpkgs homeManager system; };
  inherit (t) pkgs lib;
  wallpapers = [
    {
      monitor = "DP-1";
      wallpaper = "2270407932";
    }
    {
      monitor = "HDMI-A-1";
      wallpaper = "/home/test/wallpapers/a 'quoted' wallpaper";
    }
  ];
  base = t.cfgFor [ ];
  cfg = t.hmFor [
    {
      modules.linux-wallpaperengine = {
        enable = true;
        inherit wallpapers;
      };
    }
  ];
  service = cfg.systemd.user.services.linux-wallpaperengine;
  enable = {
    modules.linux-wallpaperengine = {
      enable = true;
      inherit wallpapers;
    };
  };
  package = pkgs.linux-wallpaperengine.overrideAttrs (_: {
    version = "test";
  });
  overridden =
    map
      (
        settings:
        t.hmFor [
          enable
          {
            home-manager.users.test.services.linux-wallpaperengine = settings;
          }
        ]
      )
      [
        { inherit package; }
        { assetsPath = "/home/test/My Assets"; }
        { assetsPath = null; }
        {
          audio = {
            silent = false;
            processing = true;
            automute = false;
          };
        }
        {
          fps = 30;
          extraOptions = [ "--no-fullscreen-pause" ];
        }
        {
          wallpapers = [
            {
              monitor = "HDMI-A-2";
              wallpaper = "different";
              scaling = "fit";
              extraOptions = [ "--disable-particles" ];
            }
          ];
        }
        {
          wallpapers = [
            {
              monitor = "DP-1";
              playlist = "My Playlist";
            }
          ];
        }
      ];
  cursor = t.hmFor [
    enable
    {
      home-manager.users.test.home.pointerCursor = {
        name = "Adwaita";
        size = 24;
        package = pkgs.adwaita-icon-theme;
      };
    }
  ];
  invalidScaling = builtins.tryEval (
    builtins.deepSeq
      (t.hmFor [
        enable
        {
          home-manager.users.test.services.linux-wallpaperengine.wallpapers = [
            {
              monitor = "DP-1";
              wallpaper = "123";
              scaling = "invalid";
            }
          ];
        }
      ]).services.linux-wallpaperengine.wallpapers
      true
  );
in
assert !base.modules.linux-wallpaperengine.enable;
assert base.modules.linux-wallpaperengine.wallpapers == [ ];
assert cfg.services.linux-wallpaperengine.enable;
assert lib.elem pkgs.linux-wallpaperengine cfg.home.packages;
assert
  cfg.services.linux-wallpaperengine.assetsPath
  == "/home/test/.local/share/Steam/steamapps/common/wallpaper_engine/assets";
assert cfg.services.linux-wallpaperengine.audio.silent;
assert !cfg.services.linux-wallpaperengine.audio.processing;
assert builtins.length cfg.services.linux-wallpaperengine.wallpapers == 2;
assert (builtins.head cfg.services.linux-wallpaperengine.wallpapers).scaling == "fill";
assert
  (builtins.elemAt cfg.services.linux-wallpaperengine.wallpapers 1).wallpaper
  == "/home/test/wallpapers/a 'quoted' wallpaper";
assert (builtins.elemAt cfg.services.linux-wallpaperengine.wallpapers 1).scaling == "fill";
assert
  (builtins.head (builtins.elemAt overridden 5).services.linux-wallpaperengine.wallpapers).scaling
  == "fit";
assert lib.hasSuffix "/bin/linux-wallpaperengine-commands" (
  builtins.head service.Service.ExecStart
);
assert
  service.Service.Environment == [
    "XCURSOR_THEME=Custom-Cursors"
    "XCURSOR_SIZE=48"
    "HYPRCURSOR_THEME=Custom-Cursors"
    "HYPRCURSOR_SIZE=48"
  ];
assert service.Install.WantedBy == [ "graphical-session.target" ];
assert cfg.home.activationPackage.drvPath != "";
# The launcher derivation must reflect each effective HM override, not only the NixOS API.
assert lib.all (
  home:
  home.systemd.user.services.linux-wallpaperengine.Service.ExecStart != service.Service.ExecStart
) overridden;
assert lib.elem package (builtins.head overridden).home.packages;
assert
  cursor.systemd.user.services.linux-wallpaperengine.Service.Environment == [
    "XCURSOR_THEME=Adwaita"
    "XCURSOR_SIZE=24"
    "HYPRCURSOR_THEME=Adwaita"
    "HYPRCURSOR_SIZE=24"
  ];
assert !invalidScaling.success;
true
