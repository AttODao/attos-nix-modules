{
  config,
  lib,
  pkgs,
  attopkgs,
  ...
}:
let
  cfg = config.modules.limine;
in
{
  config = lib.mkIf cfg.enable {
    boot = {
      # Neither desktop Zen nor server XanMod is universal; select those on the host.
      kernelPackages = lib.mkDefault pkgs.linuxPackages;
      plymouth = lib.mkIf cfg.quietBoot (
        {
          enable = lib.mkDefault true;
        }
        // lib.optionalAttrs (cfg.splashImage != null) {
          theme = lib.mkDefault "centered-logo";
          themePackages = lib.mkDefault [
            (attopkgs.centered-plymouth-theme { image = cfg.splashImage; })
          ];
        }
      );
      consoleLogLevel = lib.mkIf cfg.quietBoot (lib.mkDefault 3);
      initrd.verbose = lib.mkIf cfg.quietBoot (lib.mkDefault false);
      # Add to NixOS/Plymouth parameters rather than replacing their lists.
      kernelParams = lib.mkIf cfg.quietBoot [
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
