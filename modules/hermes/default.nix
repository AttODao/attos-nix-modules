{ config, lib, ... }:
let
  ps = import ../public-services/lib.nix { inherit lib; };
  selected = ps.select config "hermes";
  account =
    kind:
    lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "hermes";
      description = "Existing consumer-owned ${kind} running Hermes and owning dataDir.";
    };
in
{
  imports = [ ./nixos.nix ];

  options.modules = ps.moduleOptions "hermes" (
    ps.common "Hermes Agent gateway and dashboard as sandboxed native services"
    // {
      private = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Keep this management dashboard out of public CNAMEs and behind the gateway's private-network allowlist.";
      };
      backendUrl = lib.mkOption {
        type = lib.types.nullOr lib.types.nonEmptyStr;
        default = null;
        description = "HTTP upstream of the dashboard reachable by the gateway; required for every enabled record.";
      };
      dataDir = ps.pathOption "Writable state directory (HOME): HERMES_HOME is <dataDir>/.hermes and the workspace <dataDir>/workspace. The only host path visible to Hermes besides the system.";
      user = account "account";
      group = account "group";
    }
  );

  config.assertions =
    selected.assertions
    ++ lib.concatMap (entry: [
      {
        assertion = entry.cfg.private;
        message = "hermes: password-authenticated dashboards must remain private; use VPN access.";
      }
      {
        assertion = entry.cfg.backendUrl != null;
        message = "hermes: backendUrl is required for ${entry.hostname}.";
      }
    ]) (ps.entries config "hermes")
    ++ lib.optional selected.enabled {
      # A user manager would run cron workers outside the sandboxed units.
      assertion = !(config.users.users.${selected.cfg.user}.linger or false == true);
      message = "hermes: users.users.${selected.cfg.user}.linger must stay disabled; cron then runs inside the sandboxed gateway.";
    };
}
