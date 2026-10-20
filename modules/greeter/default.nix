{ config, lib, ... }:
{
  imports = [
    ./nixos.nix
    ../hyprland
    ../desktop-theme
  ];

  options.modules.greeter = {
    enable = lib.mkEnableOption "shared Noctalia greeter configuration";
    cursor = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = config.modules.desktop-theme.cursor;
      defaultText = lib.literalExpression "config.modules.desktop-theme.cursor";
      description = "Cursor archive supplied by the consumer, for example with pkgs.fetchurl; required when the greeter is enabled. Defaults to the desktop-theme cursor.";
    };
    output = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Greeter output name; null leaves output selection to Noctalia.";
    };
    defaultUser = lib.mkOption {
      type = lib.types.nullOr lib.types.nonEmptyStr;
      default = null;
      description = "Account preselected in the greeter; null leaves the user field empty.";
    };
  };

  config = lib.mkIf config.modules.greeter.enable {
    modules.hyprland.enable = true;
  };
}
