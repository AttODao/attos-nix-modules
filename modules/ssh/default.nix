{ config, lib, ... }:
{
  imports = [ ./nixos.nix ];

  options.modules.ssh = lib.mkOption {
    default = { };
    description = "SSH client enable switch and additional Host blocks using OpenSSH directive names.";
    type = lib.types.submodule {
      freeformType = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
      options.enable = lib.mkEnableOption "shared SSH client configuration";
    };
  };

  config = lib.mkIf config.modules.ssh.enable {
    home-manager.sharedModules = [ ./home.nix ];
  };
}
