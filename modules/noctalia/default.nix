{ config, lib, ... }:
let
  publicServices = import ../public-services/lib.nix { inherit lib; };
in
{
  imports = [ ./nixos.nix ];

  options.modules.noctalia = {
    enable = lib.mkEnableOption "shared Noctalia configuration";
    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = "Optional Noctalia package from a separately pinned input; null retains the host package.";
    };
    systemd = {
      enable = lib.mkEnableOption "Noctalia user service instead of direct compositor startup";
      requires = lib.mkOption {
        type = lib.types.listOf lib.types.nonEmptyStr;
        default = [ ];
        description = "User units required by the Noctalia service; applied only with the effective HM systemd launcher.";
      };
      after = lib.mkOption {
        type = lib.types.listOf lib.types.nonEmptyStr;
        default = [ ];
        description = "User units ordered before the Noctalia service; does not create those units.";
      };
    };
    dock.pinned = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Desktop entry IDs pinned to the dock (replaces the default list).";
    };
    location.address = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Location address for Noctalia; null leaves it unspecified.";
    };
    calendar.accounts = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.nonEmptyStr;
              description = "Display name of the CalDAV account.";
            };
            color = lib.mkOption {
              type = lib.types.nonEmptyStr;
              description = "Calendar color understood by Noctalia.";
            };
            serverUrl = lib.mkOption {
              type = lib.types.nonEmptyStr;
              description = "CalDAV server URL.";
            };
            username = lib.mkOption {
              type = lib.types.nonEmptyStr;
              description = "CalDAV login username.";
            };
            calendars = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ ];
              description = "Calendar identifiers selected for this account.";
            };
            passwordFile = publicServices.pathOption "Absolute runtime password file path (not a Nix store path); null leaves credentials unspecified. The consumer supplies the file and permissions.";
          };
        }
      );
      default = { };
      description = "Custom CalDAV accounts keyed by account ID, applied as adjustable defaults to every Home Manager user.";
    };
    screenRecorder = {
      enable = lib.mkEnableOption "Noctalia screen recorder";
      source = lib.mkOption {
        type = lib.types.nonEmptyStr;
        default = "portal";
        description = "Recording source understood by the Noctalia recorder plugin.";
      };
      codec = lib.mkOption {
        type = lib.types.nonEmptyStr;
        default = "h264";
        description = "Video codec understood by the Noctalia recorder plugin.";
      };
      convertToX.enable = lib.mkEnableOption "automatic HDR-to-SDR recording conversion for X (requires screenRecorder.enable)";
    };
  };

  config = lib.mkIf config.modules.noctalia.enable {
    home-manager.sharedModules = [ ./home.nix ];
  };
}
