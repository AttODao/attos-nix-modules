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
    certificates = mkOption {
      type = types.listOf (types.strMatching "[A-Za-z0-9.-]+:[0-9]+");
      default = [ ];
      example = [
        "git.example.org:443"
        "mail.example.org:993"
      ];
      description = "TLS endpoints (`host:port`, TLS from the first byte, no STARTTLS) whose certificate the collector reads on every run. The report lists expiry date and days left; a certificate that fails verification (expired, wrong name, untrusted issuer) or has fewer than `alert.certificateDays` days left is a problem. A connection failure (after one retry) is a collection error. Use a name this host can reach.";
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
      smartPercentageUsed = mkOption {
        type = types.nullOr (types.ints.between 1 255);
        default = 80;
        description = "NVMe percentage used warning threshold; null disables this check. Spare at or below its threshold + 10 percentage points always warns.";
      };
      diskWritesPerDayGB = mkOption {
        type = types.nullOr types.ints.positive;
        default = null;
        description = "Disk writes in decimal GB per rolling 24h above which to warn; null disables. Requires a complete history window; partial intervals are not extrapolated.";
      };
      certificateDays = mkOption {
        type = types.ints.positive;
        default = 20;
        description = "Days left on a certificate in `certificates` below which to alert. ACME clients renew about 30 days before expiry, so the default means renewal has been failing for about 10 days.";
      };
      diskPercent = mkOption {
        type = types.ints.between 1 100;
        default = 90;
        description = "Disk usage percentage triggering an alert.";
      };
    };
    logChecks = mkOption {
      default = { };
      description = "Journal checks; native enabled services get overridable defaults. Only regex captures, never raw messages, enter the report. Patterns use Python re syntax and see messages without terminal colour codes.";
      type = types.attrsOf (
        types.submodule {
          options = {
            units = mkOption {
              type = types.listOf types.nonEmptyStr;
              description = "Journal system units to match.";
            };
            pattern = mkOption {
              type = types.nonEmptyStr;
              description = "Event regex. Named user, command and action groups become bounded summaries. With `alertWindow`, the named group `error` (or the whole match) is kept, cut to 300 characters, so it must not capture secrets.";
            };
            ipPattern = mkOption {
              type = types.nullOr types.nonEmptyStr;
              default = null;
              description = "Optional regex whose first capture is validated as an IP address.";
            };
            alertWindow = mkOption {
              type = types.nullOr types.ints.positive;
              default = null;
              description = "When set, a single match is a problem, reported with its text until no further match arrives for this many seconds. Choose more than the interval at which the service retries, otherwise the alert resolves and reopens between retries. For errors the journal priority does not show (services that log failures at info level).";
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
