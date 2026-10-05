{ config, lib, ... }:
{
  imports = [
    ./nixos.nix
    ../noctalia
    ../fcitx5
    ../foot
    ../pcmanfm
    ../userDirs
  ];

  options.modules.hyprland = {
    enable = lib.mkEnableOption "shared Hyprland configuration";
    monitors = lib.mkOption {
      type =
        with lib.types;
        listOf (submodule {
          options = {
            output = lib.mkOption {
              type = str;
              default = "";
            };
            mode = lib.mkOption {
              type = str;
              default = "preferred";
            };
            position = lib.mkOption {
              type = str;
              default = "auto";
            };
            scale = lib.mkOption {
              type = numbers.positive;
              default = 1;
            };
            bitdepth = lib.mkOption {
              type = nullOr (enum [
                8
                10
              ]);
              default = null;
            };
            cm = lib.mkOption {
              type = nullOr str;
              default = null;
            };
          };
        });
      default = [ { } ];
      description = "Monitor layout; defaults to the portable preferred-mode output.";
    };
    neowall.enable = lib.mkEnableOption "neowall startup with the fixed wallpaper shader";
    lidSwitch.enable = lib.mkEnableOption "Noctalia monitor on/off bindings for the lid switch";
  };

  config = lib.mkIf config.modules.hyprland.enable {
    modules.noctalia.enable = true;
    modules.fcitx5.enable = true;
    modules.foot.enable = true;
    modules.pcmanfm.enable = true;
    modules.userDirs.enable = true;
    home-manager.sharedModules = [ ./home.nix ];
  };
}
