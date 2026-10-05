{
  config,
  lib,
  pkgs,
  ...
}:
let
  tomlFormat = pkgs.formats.toml { };
in
{
  options.modules.noctalia = {
    enable = lib.mkEnableOption "shared Noctalia configuration";
    dock.pinned = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
      ];
      description = "Desktop entry IDs pinned to the dock (replaces the default list).";
    };
    screenRecorder.enable = lib.mkEnableOption "Noctalia screen recorder";
    calendar.account = lib.mkOption {
      type = lib.types.attrsOf tomlFormat.type;
      default = { };
      description = "Noctalia calendar accounts keyed by ID; use password_file for runtime credentials.";
    };
    location = lib.mkOption {
      type = lib.types.attrsOf tomlFormat.type;
      default = { };
      description = "Noctalia location settings, for example { address = \"Toyoake, Japan\"; }.";
    };
  };

  config = lib.mkIf config.modules.noctalia.enable {
    home-manager.sharedModules = [ ./home.nix ];
  };
}
