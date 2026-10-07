# nix-instantiate --eval --strict tests/pcmanfm-user-dirs.nix \
#   --arg nixpkgs /path/to/nixpkgs --arg homeManager /path/to/home-manager
{
  nixpkgs,
  homeManager,
  system ? builtins.currentSystem,
}:
let
  t = import ./lib.nix { inherit nixpkgs homeManager system; };
  inherit (t) pkgs lib;
  base = t.cfgFor [ ];
  pcmanfm = t.hmFor [ { modules.pcmanfm.enable = true; } ];
  customMime = t.hmFor [
    {
      modules.pcmanfm.enable = true;
      home-manager.users.test.xdg.mimeApps.defaultApplications = {
        "inode/directory" = [ "thunar.desktop" ];
        "x-directory/normal" = [ "thunar.desktop" ];
      };
    }
  ];
  userDirs = t.hmFor [ { modules.userDirs.enable = true; } ];
  relocated = t.hmFor [
    {
      modules.userDirs.enable = true;
      users.users.test.home = "/home/other";
    }
  ];
  both = t.hmFor [
    {
      modules.pcmanfm.enable = true;
      modules.userDirs = {
        enable = true;
        dataDirectory = "/mnt/data";
      };
    }
  ];
  dataDirectories = [
    "documents"
    "download"
    "music"
    "pictures"
    "videos"
  ];
  homeDirectories = [
    "desktop"
    "publicShare"
    "templates"
  ];
  invalidPath =
    builtins.tryEval
      (t.cfgFor [ { modules.userDirs.dataDirectory = "relative"; } ]).modules.userDirs.dataDirectory;
  invalidPathLiterals = map (
    option:
    builtins.tryEval (t.cfgFor [ { modules.userDirs.${option} = /tmp; } ]).modules.userDirs.${option}
  ) [ "dataDirectory" ];
  multi =
    (t.evalSystem {
      users = [
        "alice"
        "bob"
      ];
      modules = [
        {
          modules.userDirs.enable = true;
          users.users.bob.home = "/srv/bob";
          home-manager.users.alice.xdg.userDirs = {
            videos = "/srv/alice/video";
            createDirectories = false;
          };
        }
      ];
    }).config;
in
assert !base.modules.pcmanfm.enable && !base.modules.userDirs.enable;
assert lib.elem pkgs.pcmanfm pcmanfm.home.packages;
assert !pcmanfm.xdg.userDirs.enable;
assert !(pcmanfm.home.activation ? createXdgUserDirectories);
assert pcmanfm.xdg.mimeApps.defaultApplications."inode/directory" == [ "pcmanfm.desktop" ];
assert pcmanfm.xdg.mimeApps.defaultApplications."x-directory/normal" == [ "pcmanfm.desktop" ];
assert customMime.xdg.mimeApps.defaultApplications."inode/directory" == [ "thunar.desktop" ];
assert customMime.xdg.mimeApps.defaultApplications."x-directory/normal" == [ "thunar.desktop" ];
assert lib.elem "Exec=${pkgs.pcmanfm}/bin/pcmanfm %U" (
  lib.splitString "\n" pcmanfm.xdg.dataFile."applications/pcmanfm.desktop".text
);
assert pcmanfm.xdg.dataFile."icons/hicolor/256x256/apps/pcmanfm.png".source.drvPath != "";
assert userDirs.xdg.userDirs.enable && userDirs.xdg.userDirs.createDirectories;
assert userDirs.xdg.userDirs.desktop == "/home/test/Desktop";
assert userDirs.xdg.userDirs.documents == "/home/test/Documents";
assert userDirs.home.activation ? createXdgUserDirectories;
assert !(lib.elem pkgs.pcmanfm userDirs.home.packages);
assert !(userDirs.xdg.dataFile ? "applications/pcmanfm.desktop");
assert lib.all (name: lib.hasPrefix "/home/other/" relocated.xdg.userDirs.${name}) (
  homeDirectories ++ dataDirectories
);
assert lib.all (name: lib.hasPrefix "/home/test/" both.xdg.userDirs.${name}) homeDirectories;
assert both.xdg.userDirs.documents == "/mnt/data/Documents";
assert both.xdg.userDirs.download == "/mnt/data/Downloads";
assert both.xdg.userDirs.music == "/mnt/data/Music";
assert both.xdg.userDirs.pictures == "/mnt/data/Pictures";
assert both.xdg.userDirs.videos == "/mnt/data/Videos";
assert both.home.homeDirectory == "/home/test";
assert !(both.home.file ? "Pictures/Screenshots/.keep");
assert pcmanfm.home.activationPackage.drvPath != "";
assert userDirs.home.activationPackage.drvPath != "";
assert both.home.activationPackage.drvPath != "";
assert !invalidPath.success;
assert lib.all (result: !result.success) invalidPathLiterals;
assert multi.home-manager.users.alice.xdg.userDirs.desktop == "/home/alice/Desktop";
assert multi.home-manager.users.alice.xdg.userDirs.videos == "/srv/alice/video";
assert !multi.home-manager.users.alice.xdg.userDirs.createDirectories;
assert multi.home-manager.users.bob.xdg.userDirs.documents == "/srv/bob/Documents";
assert multi.home-manager.users.bob.xdg.userDirs.videos == "/srv/bob/Videos";
assert multi.home-manager.users.bob.xdg.userDirs.createDirectories;
true
