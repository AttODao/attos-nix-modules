{ lib, ... }:
{
  imports = [ ./nixos.nix ];

  options.modules.fonts.enable = lib.mkEnableOption "shared system fonts";
}
