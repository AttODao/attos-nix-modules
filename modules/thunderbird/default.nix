{ config, lib, ... }:
{
  imports = [ ./nixos.nix ];

  options.modules.thunderbird.enable = lib.mkEnableOption "shared Thunderbird configuration";

  config = lib.mkIf config.modules.thunderbird.enable {
    home-manager.sharedModules = [ ./home.nix ];
  };
}
