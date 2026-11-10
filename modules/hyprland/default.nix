{ config, lib, ... }:
let
  # Same shape as Home Manager's wayland.windowManager.hyprland.settings value type:
  # attrsets merge recursively and lists concatenate, without evaluating the HM option tree here.
  settingValueType =
    with lib.types;
    nullOr (oneOf [
      bool
      int
      float
      str
      path
      (attrsOf settingValueType)
      (listOf settingValueType)
    ])
    // {
      description = "Hyprland configuration value";
    };
in
{
  imports = [
    ./nixos.nix
    ../noctalia
    ../fcitx5
    ../foot
    ../yazi
    ../userDirs
  ];

  options.modules.hyprland = {
    enable = lib.mkEnableOption "shared Hyprland configuration";
    settings = lib.mkOption {
      type = lib.types.attrsOf settingValueType;
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
      description = "Hyprland Lua settings (the shape of Home Manager's wayland.windowManager.hyprland.settings) for all HM users, recursively merged over the shared defaults. Lists replace the shared list, except window_rule, which is appended to the shared rules. config.general.layout = \"scrolling\" also adds the scrolling-layout binds and gestures. Every resulting leaf is a default that home-manager.users.<name> can override. List every monitor in settings.monitor, including its scale.";
    };
    neowall.enable = lib.mkEnableOption "neowall as the wallpaper (fixed neonwave_sunrise shader, started with the session); Noctalia's own wallpaper is then disabled";
    lidSwitch.enable = lib.mkEnableOption "turning the monitors off and on through Noctalia when the lid closes and opens, instead of logind's lid handling";
  };

  config = lib.mkIf config.modules.hyprland.enable {
    modules.noctalia.enable = true;
    modules.fcitx5.enable = true;
    modules.foot.enable = true;
    modules.yazi.enable = true;
    modules.userDirs.enable = true;
    home-manager.sharedModules = [ ./home.nix ];
  };
}
