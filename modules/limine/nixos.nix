{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = lib.mkIf config.modules.limine.enable {
    boot = {
      # Neither desktop Zen nor server XanMod is universal; select those on the host.
      kernelPackages = lib.mkDefault pkgs.linuxPackages;
      plymouth.enable = lib.mkDefault true;
      # Use upstream's theme by default; branded assets belong to the consumer.
      consoleLogLevel = lib.mkDefault 3;
      initrd.verbose = lib.mkDefault false;
      # Add to NixOS/Plymouth parameters rather than losing these to their normal-priority lists.
      kernelParams = [
        "quiet"
        "udev.log_level=3"
        "rd.systemd.show_status=auto"
      ];
      loader = {
        systemd-boot.enable = lib.mkDefault false;
        limine = {
          enable = true;
          maxGenerations = lib.mkDefault 10;
        };
        efi.canTouchEfiVariables = lib.mkDefault true;
      };
    };
  };
}
