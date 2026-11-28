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
    history_days = cfg.historyDays;
  }
  // lib.optionalAttrs (cfg.settleSeconds != null) { settle_secs = cfg.settleSeconds; }
  // lib.optionalAttrs (cfg.hermesPackage != null) {
    hermes_bin = "${cfg.hermesPackage}/bin/hermes";
  }
  // lib.optionalAttrs (cfg.promptListen != null) {
    prompt_listen = cfg.promptListen;
    chat_url = cfg.chatUrl;
  };
  # The Hermes CLI writes kanban.db (answers and card resumes from the dashboard).
  commands = cfg.hermesPackage != null;

  configToml = toml.generate "hypermonitor-bridge.toml" settings;
  configFile = pkgs.runCommand "hypermonitor-bridge-checked.toml" { } ''
    ${pkg}/bin/hypermonitor check-config --bridge ${configToml}
    cp ${configToml} "$out"
  '';
in
{
  options.modules.hypermonitor-bridge = {
    enable = lib.mkEnableOption "the HyperMonitor bridge: sends the Hermes morning Brief, the Kanban/cron summary and Hermes events to a HyperMonitor server's ingest listener (read-only access to the Hermes home unless `hermesPackage` is set)";
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
    hermesPackage = mkOption {
      type = types.nullOr types.package;
      default = null;
      example = lib.literalExpression "config.services.hermes-agent.package";
      description = ''
        Hermes package whose `bin/hermes` the bridge runs for answers and card resumes sent
        from the dashboard (`hermes kanban comment` / `unblock`, fixed arguments, no shell).
        Setting it makes the Hermes home writable for the unit (the CLI writes `kanban.db`)
        and allows writable executable memory (Python); null takes no commands and keeps the
        home read-only.
      '';
    };
    promptListen = mkOption {
      type = types.nullOr (types.strMatching "127[.][0-9]+[.][0-9]+[.][0-9]+:[0-9]+");
      default = null;
      example = "127.0.0.1:8652";
      description = ''
        IPv4 loopback address where the bridge receives Hermes' outbound webhook for chat questions
        (`hooks.outbound` with the events `on_session_prompt` and `on_session_prompt_settled`,
        url `http://<address>/prompt`); they become events that link to the chat. Needs `chatUrl`.
      '';
    };
    chatUrl = mkOption {
      type = types.nullOr (types.strMatching "https?://[^[:space:]]*[{]session[}][^[:space:]]*");
      default = null;
      example = "https://hermes.example/#/sessions/{session}";
      description = "Page of a chat session, `{session}` replaced by the session id (where a chat question is answered).";
    };
    historyDays = mkOption {
      type = types.ints.between 1 90;
      default = 7;
      description = "Days of Kanban and cron history the bridge sends on its first start.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = (cfg.promptListen == null) == (cfg.chatUrl == null);
        message = "modules.hypermonitor-bridge: promptListen and chatUrl go together.";
      }
    ];
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
        # Everything but the state directory is read-only; the Hermes home too unless the
        # bridge runs the Hermes CLI (it opens kanban.db itself only read-only either way).
        ProtectSystem = "strict";
        ReadOnlyPaths = lib.optional (!commands) cfg.hermesHome;
        ReadWritePaths = lib.optional commands cfg.hermesHome;
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
        MemoryDenyWriteExecute = !commands;
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
