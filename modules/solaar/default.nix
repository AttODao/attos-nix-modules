{ config, lib, ... }:
{
  imports = [
    ./nixos.nix
    ../noctalia
  ];

  options.modules.solaar = {
    enable = lib.mkEnableOption "shared Solaar configuration with Kando";
    deviceConfig = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Solaar config.yaml (device serials and per-device settings) seeded once into each HM user's ~/.config/solaar; null leaves Solaar to create it. Device identifiers belong to the consumer.";
    };
  };

  config = lib.mkIf config.modules.solaar.enable {
    modules.noctalia.enable = true;
    home-manager.sharedModules = [ ./home.nix ];
  };
}
