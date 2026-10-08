{
  config,
  options,
  lib,
  ...
}:
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
    settings = lib.mkOption {
      type =
        lib.types.attrsOf
          (options.home-manager.users.type.getSubOptions [ ]).wayland.windowManager.hyprland.settings.type;
      default = { };
      example = {
        monitor = [
          {
            output = "DP-1";
            mode = "preferred";
            scale = 1;
            cm = "hdr";
          }
        ];
        window_rule = [
          {
            match.class = "^com[.]moonlight_stream[.]Moonlight$";
            no_auto_hdr = true;
          }
        ];
      };
      description = "Hyprland Lua settings for all HM users, recursively overriding shared defaults; lists replace defaults. Each user can override these defaults through standard Home Manager settings. Monitor layout uses settings.monitor (including scale).";
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
