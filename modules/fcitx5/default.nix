{ config, lib, ... }:
{
  options.modules.fcitx5 = {
    enable = lib.mkEnableOption "shared Fcitx5 with SKK configuration";
    keyboardLayout = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Fcitx5 keyboard-us input method layout; empty inherits the group layout.";
    };
  };

  config = lib.mkIf config.modules.fcitx5.enable {
    home-manager.sharedModules = [ ./home.nix ];
  };
}
