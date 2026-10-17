{
  config,
  lib,
  pkgs,
  ...
}:
{
  options.modules.vscode = {
    enable = lib.mkEnableOption "shared VS Code configuration";
    userSettings = lib.mkOption {
      type = (pkgs.formats.json { }).type;
      default = { };
      description = "Shared VS Code user settings, applied as overridable defaults to all HM users. Keep credentials out of these store-backed values.";
    };
  };

  config = lib.mkIf config.modules.vscode.enable {
    home-manager.sharedModules = [ ./home.nix ];
  };
}
