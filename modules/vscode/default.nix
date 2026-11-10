{ config, lib, ... }:
{
  options.modules.vscode.enable = lib.mkEnableOption "shared VS Code configuration";

  config = lib.mkIf config.modules.vscode.enable {
    home-manager.sharedModules = [ ./home.nix ];
  };
}
