{ config, lib, ... }:
{
  imports = [ ./nixos.nix ];

  options.modules.opencloud-client.enable = lib.mkEnableOption "shared OpenCloud desktop client";

  config = lib.mkIf config.modules.opencloud-client.enable {
    home-manager.sharedModules = [ ./home.nix ];
  };
}
