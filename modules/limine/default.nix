{ config, lib, ... }:
{
  imports = [ ./nixos.nix ];

  options.modules.limine = {
    enable = lib.mkEnableOption "shared Limine boot configuration";
    quietBoot = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Add Plymouth and quiet console/initrd/kernel defaults; false leaves diagnostics at native NixOS defaults without adding quiet parameters.";
    };
    splashImage = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Consumer-owned image for the centered-logo Plymouth theme, resized to at most 960x360 on a black background; null leaves the upstream theme unchanged.";
    };
  };
}
