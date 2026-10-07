{ config, lib, ... }:
{
  imports = [ ./nixos.nix ];

  options.modules.limine.enable = lib.mkEnableOption "shared quiet Limine boot configuration";
}
