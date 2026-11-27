{
  config,
  lib,
  pkgs,
  ps,
  attopkgs,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.modules.hypermonitor-bridge;
  pkg = if cfg.package != null then cfg.package else attopkgs.hypermonitor;
  toml = pkgs.formats.toml { };
  stateDir = "/var/lib/${cfg.stateDirectory}";

  settings = {
    inherit (cfg) server;
    hermes_home = cfg.hermesHome;
    state_dir = stateDir;
    timezone = if config.time.timeZone != null then config.time.timeZone else "UTC";
    categories = map (c: { inherit (c) id label; }) cfg.categories;
  }
  // lib.optionalAttrs (cfg.settleSeconds != null) { settle_secs = cfg.settleSeconds; };

  configToml = toml.generate "hypermonitor-bridge.toml" settings;
  configFile = pkgs.runCommand "hypermonitor-bridge-checked.toml" { } ''
    ${pkg}/bin/hypermonitor check-config --bridge ${configToml}
    cp ${configToml} "$out"
  '';
in
{
  options.modules.hypermonitor-bridge = {
    enable = lib.mkEnableOption "the HyperMonitor bridge: sends the Hermes morning Brief and the Kanban/cron summary to a HyperMonitor server's ingest listener (read-only access to the Hermes home)";
    server = mkOption {
      type = types.strMatching "https?://[^/[:space:]]+/?";
      example = "http://10.0.0.1:8651";
      description = "Base URL of the server's ingest listener (`modules.hypermonitor` `ingestListen`); that server must list this host in `ingestPeers`.";
    };
    hermesHome = mkOption {
      type = ps.absolutePath;
      default = "/var/lib/hermes/.hermes";
      description = "Hermes home (HERMES_HOME) read by the bridge: `cache/morning-brief/<date>/`, `kanban.db`, `cron/jobs.json`.";
    };
    user = mkOption {
      type = types.nonEmptyStr;
      default = "hermes";
      description = "Existing user the bridge runs as; it must be able to read the Hermes home. The unit mounts the file system read-only except its state directory.";
    };
    stateDirectory = mkOption {
      type = types.strMatching "[a-z][a-z0-9-]*";
      default = "hypermonitor-bridge";
      description = "Name of the state directory under /var/lib (what was uploaded, so restarts send nothing again).";
    };
    categories = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            id = mkOption {
              type = types.strMatching "[A-Za-z0-9._:-]+";
              description = "News category id (the `<id>` of `news-<id>.json`).";
            };
            label = mkOption {
              type = types.nonEmptyStr;
              description = "Tab label shown for the category.";
            };
          };
        }
      );
      default = [ ];
      description = "Labels of the Brief's news categories, in display order; categories without an entry follow by name, labelled with their id.";
    };
    settleSeconds = mkOption {
      type = types.nullOr types.ints.positive;
      default = null;
      description = "Seconds a day's Brief files must stay unchanged before they are sent; null keeps the bridge default (30).";
    };
    package = mkOption {
      type = types.nullOr types.package;
      default = null;
      description = "HyperMonitor package (bin/hypermonitor); null uses attopkgs.hypermonitor.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.hypermonitor-bridge = ps.afterNetworkOnline // {
      description = "HyperMonitor bridge (Brief and Hermes summary to the dashboard)";
      wantedBy = [ "multi-user.target" ];
      environment.RUST_LOG = lib.mkDefault "info";
      serviceConfig = {
        ExecStart = "${pkg}/bin/hypermonitor bridge --config ${configFile}";
        User = cfg.user;
        StateDirectory = cfg.stateDirectory;
        StateDirectoryMode = "0700";
        Restart = "always";
        RestartSec = 10;
        # Everything but the state directory is read-only (the Hermes home included).
        ProtectSystem = "strict";
        ReadOnlyPaths = [ cfg.hermesHome ];
        ProtectHome = true;
        NoNewPrivileges = true;
        PrivateTmp = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        ProtectClock = true;
        ProtectHostname = true;
        ProtectProc = "invisible";
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        SystemCallArchitectures = "native";
        CapabilityBoundingSet = "";
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
        ];
        UMask = "0077";
      };
    };
  };
}
