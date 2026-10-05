{ config, lib, ... }:
{
  imports = [ ./nixos.nix ];

  options.modules.pipewire.enable = lib.mkEnableOption "shared PipeWire audio support";

  config = lib.mkIf config.modules.pipewire.enable {
  };
}
