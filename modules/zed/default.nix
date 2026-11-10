{ config, lib, ... }:
{
  options.modules.zed = {
    enable = lib.mkEnableOption "shared Zed editor configuration";
    installEditor = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install the Zed editor. Disable on hosts used only as SSH remote targets: the managed settings.json is still written, and the remote server Zed uploads there reads it.";
    };
  };

  config = lib.mkIf config.modules.zed.enable {
    home-manager.sharedModules = [ ./home.nix ];
  };
}
