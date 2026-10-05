{ config, lib, ... }:
{
  imports = [ ./nixos.nix ];
  options.modules.docker.enable = lib.mkEnableOption "shared Docker and OCI service support";
}
