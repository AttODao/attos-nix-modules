{
  config,
  lib,
  ps,
  ...
}:
let
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
      dataDir = ps.pathOption "Writable state directory (HOME): HERMES_HOME is <dataDir>/.hermes and the workspace <dataDir>/workspace. The only writable host path; additional read-only paths require explicit readOnlyPaths.";
      readOnlyPaths = lib.mkOption {
        type = lib.types.listOf (
          lib.types.addCheck ps.absolutePath (
            path:
            lib.all (character: !lib.hasInfix character path) [
              "%"
              " "
              "\t"
              "\\"
              "\""
              "'"
            ]
          )
        );
        default = [ ];
        description = "Explicit read-only host paths visible in both default-deny sandboxes; absent paths are ignored. Does not grant write access or bypass Unix permissions. Do not expose credentials or management sockets.";
      };
      sandbox = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Run both units in the default-deny filesystem sandbox. Set false only when the whole OS is a dedicated trust boundary for Hermes (for example its own container): the units then see the whole filesystem, the hermes CLI is installed system-wide, and HERMES_HOME, HERMES_MANAGED and HERMES_MANAGED_DIR are exported to every PAM session so login shells and Hermes Desktop SSH connections (which start `hermes serve` over SSH) share the gateway's state and managed scope. This also disables upstream NoNewPrivileges, ProtectSystem and PrivateTmp so tools can use consumer-granted sudo and write across the system, with /tmp shared with SSH sessions. readOnlyPaths must then stay empty.";
      };
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
    ++ lib.optional (selected.enabled && selected.cfg.sandbox) {
      # A user manager would run cron workers outside the sandboxed units.
      assertion = !(config.users.users.${selected.cfg.user}.linger or false == true);
      message = "hermes: users.users.${selected.cfg.user}.linger must stay disabled; cron then runs inside the sandboxed gateway.";
    }
    ++ lib.optional (selected.enabled && !selected.cfg.sandbox) {
      assertion = selected.cfg.readOnlyPaths == [ ];
      message = "hermes: readOnlyPaths only applies to the sandbox; the unsandboxed units already see the whole filesystem.";
    };
}
