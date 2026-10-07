{ config, lib, ... }:
{
  imports = [ ./nixos.nix ];

  options.modules.limine = {
    enable = lib.mkEnableOption "shared quiet Limine boot configuration";
    splashImage = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Consumer-owned image for the centered-logo Plymouth theme, resized to at most 960x360 on a black background; null leaves the upstream theme unchanged.";
    };
  };
}
