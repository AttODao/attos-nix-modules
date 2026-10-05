{ config, lib, ... }:
{
  imports = [
    ./nixos.nix
    ../hyprland
  ];

  options.modules.greeter = {
    enable = lib.mkEnableOption "shared Noctalia greeter configuration";
    cursor = lib.mkOption {
      type = lib.types.package;
      description = "Cursor archive supplied by the consumer, for example with pkgs.fetchurl; required when the greeter is enabled.";
    };
    output = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Greeter output name; null leaves output selection to Noctalia.";
    };
  };

  config = lib.mkIf config.modules.greeter.enable {
    modules.hyprland.enable = true;
  };
}
