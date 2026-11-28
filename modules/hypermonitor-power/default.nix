{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.modules.hypermonitor-power;
  systemctl = "${config.systemd.package}/bin/systemctl";
  # The agent's `start` returns once the process runs; the 2 s wait lets its answer and the
  # SSH session end before the machine goes down. logind (not `start poweroff.target`)
  # keeps delay inhibitors such as shutdown-hold in effect.
  unit = verb: description: {
    inherit description;
    serviceConfig = {
      Type = "exec";
      ExecStart = pkgs.writeShellScript "hypermonitor-${verb}" ''
        sleep 2
        exec ${systemctl} ${verb}
      '';
    };
  };
in
{
  options.modules.hypermonitor-power = {
    enable = lib.mkEnableOption "the units a HyperMonitor dashboard starts (through attos-deck-agent) to suspend or power off this host, `hypermonitor-suspend.service` and `hypermonitor-poweroff.service`; the dashboard checks the host's running jobs first";
    publishJobs = mkOption {
      type = types.bool;
      default = true;
      description = "Publish the attos-jobs status (`/run/attos-jobs/status.json`: running jobs and local logins) as `attos-jobs.json` next to the host report (modules.host-report publish), where the dashboard reads it before suspending or powering off (`[[hosts]] jobs`). Needs modules.attos-jobs and the host-report publisher.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.modules.attos-deck.agent.enable;
        message = "hypermonitor-power: the dashboard starts the units through attos-deck-agent; enable modules.attos-deck.agent.";
      }
      {
        assertion =
          !cfg.publishJobs || (config.modules.attos-jobs.enable && config.modules.host-report.publish.enable);
        message = "hypermonitor-power.publishJobs needs modules.attos-jobs and modules.host-report.publish.";
      }
    ];

    systemd.services.hypermonitor-suspend = unit "suspend" "Suspend on request of the HyperMonitor dashboard";
    systemd.services.hypermonitor-poweroff = unit "poweroff" "Power off on request of the HyperMonitor dashboard";

    # The agent may start these two units and read their state, nothing else of power.
    modules.attos-deck.agent.settings.units = {
      "hypermonitor-suspend.service".allow = [
        "start"
        "status"
      ];
      "hypermonitor-poweroff.service".allow = [
        "start"
        "status"
      ];
    };

    # darkhttpd follows the link and reads the file the agent replaces every 5 s.
    systemd.tmpfiles.rules = lib.mkIf cfg.publishJobs [
      "L+ /var/lib/host-report-publish/attos-jobs.json - - - - /run/attos-jobs/status.json"
    ];
  };
}
