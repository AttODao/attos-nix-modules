{ lib, ... }:
let
  inherit (lib) mkOption types;
  text =
    default: description:
    mkOption {
      type = types.nonEmptyStr;
      inherit default description;
    };
  seconds =
    default: description:
    mkOption {
      type = types.ints.positive;
      inherit default description;
    };
in
{
  imports = [ ./nixos.nix ];
  options.modules.host-report = {
    enable = lib.mkEnableOption "root-collected, read-only host reports";
    onCalendar = text "*:0/15" "systemd calendar for collection and remote fetches.";
    readerGroup = mkOption {
      type = types.nullOr types.nonEmptyStr;
      default = null;
      description = "Existing reader group; report directory is root:group 0750 and reports 0640. Private cursors and alert state remain root-only.";
    };
    publish = {
      enable = lib.mkEnableOption "HTTP publication of only this host's report (no firewall opening)";
      address = mkOption {
        type = types.nullOr types.nonEmptyStr;
        default = null;
        description = "Explicit local bind address, required when publishing; restrict access in the consumer firewall.";
      };
      port = mkOption {
        type = types.port;
        default = 9180;
        description = "Static HTTP listen port.";
      };
    };
    fetch = mkOption {
      default = { };
      description = "Remote reports keyed by host name. HTTP is appropriate only on a trusted, firewall-restricted link.";
      type = types.attrsOf (
        types.submodule {
          options.url = mkOption {
            type = types.strMatching "https?://[^[:space:]]+";
            description = "URL of the peer's JSON report.";
          };
        }
      );
    };
    alert = {
      enable = lib.mkEnableOption "deduplicated sendmail alerts and recovery notices";
      to = mkOption {
        type = types.nullOr (types.strMatching "[^\r\n]+");
        default = null;
        description = "Recipient required when alerts are enabled.";
      };
      from = mkOption {
        type = types.nullOr (types.strMatching "[^\r\n]+");
        default = null;
        description = "Optional From address; otherwise root@host.";
      };
      sendmail = text "/run/wrappers/bin/sendmail" "Absolute sendmail-compatible executable; the consumer supplies an MTA. Postfix queue paths are writable in the collector sandbox.";
      repeatInterval = seconds 86400 "Seconds between reminders for ongoing problems.";
      staleAfter = seconds 3600 "Maximum report age in seconds, including remote reports.";
      authFailures = seconds 20 "Matching failure events per collection interval before alerting.";
      diskPercent = mkOption {
        type = types.ints.between 1 100;
        default = 90;
        description = "Disk usage percentage triggering an alert.";
      };
    };
    logChecks = mkOption {
      default = { };
      description = "Journal checks; native enabled services get overridable defaults. Only regex captures, never raw messages, enter the report. Patterns use Python re syntax.";
      type = types.attrsOf (
        types.submodule {
          options = {
            units = mkOption {
              type = types.listOf types.nonEmptyStr;
              description = "Journal system units to match.";
            };
            pattern = mkOption {
              type = types.nonEmptyStr;
              description = "Event regex. Named user, command and action groups become bounded summaries.";
            };
            ipPattern = mkOption {
              type = types.nullOr types.nonEmptyStr;
              default = null;
              description = "Optional regex whose first capture is validated as an IP address.";
            };
            failure = mkOption {
              type = types.bool;
              default = true;
              description = "Count towards the authentication failure threshold; disable for successful logins, sudo and bans.";
            };
          };
        }
      );
    };
  };
}
