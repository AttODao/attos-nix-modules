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
      scaling = "fit";
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
  invalidScaling = builtins.tryEval (
    builtins.deepSeq
      (t.cfgFor [
        {
          modules.linux-wallpaperengine.wallpapers = [
            {
              monitor = "DP-1";
              wallpaper = "123";
              scaling = "invalid";
            }
          ];
        }
      ]).modules.linux-wallpaperengine.wallpapers
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
assert (builtins.elemAt cfg.services.linux-wallpaperengine.wallpapers 1).scaling == "fit";
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
assert !invalidScaling.success;
true
