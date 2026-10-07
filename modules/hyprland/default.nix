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
    headless = {
      enable = lib.mkEnableOption "container headless UWSM session, seatd, input nodes and named output";
      outputName = lib.mkOption {
        type = lib.types.nonEmptyStr;
        default = "moonlight";
        description = "Name passed to hyprctl output create/remove; monitor modes remain consumer configuration.";
      };
      seatGroup = lib.mkOption {
        type = lib.types.nonEmptyStr;
        default = "render";
        description = "Group allowed to access seatd. Membership and numeric IDs belong to the consumer.";
      };
      inputGroup = lib.mkOption {
        type = lib.types.nonEmptyStr;
        default = "input";
        description = "Group owning container input event nodes; numeric IDs belong to the consumer.";
      };
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
