{ config, lib, ... }:
{
  imports = [ ./nixos.nix ];

  options.modules.ssh.enable = lib.mkEnableOption "shared SSH client configuration";

  config = lib.mkIf config.modules.ssh.enable {
    home-manager.sharedModules = [ ./home.nix ];
  };
}
