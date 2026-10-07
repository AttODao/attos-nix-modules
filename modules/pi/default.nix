{ config, lib, ... }:
{
  imports = [ ./nixos.nix ];

  options.modules.pi = {
    enable = lib.mkEnableOption "shared Pi configuration";
    settingsMode = lib.mkOption {
      type = lib.types.enum [
        "declarative"
        "merge"
      ];
      default = "declarative";
      description = "Manage settings.json declaratively, or merge defaults into a writable user-owned 0600 file, preserving existing settings recursively. Invalid JSON fails activation without replacing the file.";
    };
    piSessionsSource = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = "Pinned pi-sessions extension source package; null uses the shared revision.";
    };
    systemWide = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Also install the shared Pi and context-mode CLIs system-wide.";
    };
  };

  config = lib.mkIf config.modules.pi.enable {
    home-manager.sharedModules = [ ./home.nix ];
  };
}
