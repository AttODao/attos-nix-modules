{
  config,
  lib,
  pkgs,
  ps,
  attopkgs,
  ...
}:
let
  # The Traefik gateway runs the strata-wake gate for the registered owner with wake enabled.
  wakeEntries = lib.filter (entry: entry.cfg.deploy && entry.cfg.wake.enable) (
    ps.entries config "strata"
  );
  entry = builtins.head wakeEntries;
  w = entry.cfg.wake;
  gateConfig = pkgs.writeText "strata-wake-gate.json" (
    builtins.toJSON {
      listen = w.gatewayListen;
      backendUrl = ps.require "strata" "backendUrl" entry.cfg.backendUrl;
      healthPath = "/health";
      controlUrl = lib.removeSuffix "/" w.controlUrl;
      wol =
        if w.macAddress == null then
          null
        else
          {
            mac = w.macAddress;
            inherit (w) broadcast;
          };
      idleTimeoutSec = w.idleMinutes * 60;
      powerOff = w.powerOff && w.macAddress != null;
      wakeTimeoutSec = 300;
      startTimeoutSec = 900;
      stateFile = "/var/lib/strata-wake/state.json";
    }
  );
in
{
  config = lib.mkIf (config.modules.traefik.enable && wakeEntries != [ ]) {
    assertions = [
      {
        assertion = builtins.length wakeEntries == 1;
        message = "strata: only one registry entry with wake enabled is supported per gateway.";
      }
    ];
    # Traefik routes the entry to wake.gatewayListen (public-services lib `upstream`);
    # this proxy forwards to backendUrl and starts Strata on demand.
    systemd.services.strata-wake-gate = lib.mkMerge [
      ps.afterNetworkOnline
      {
        description = "Strata on-demand gateway proxy";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          DynamicUser = true;
          StateDirectory = "strata-wake";
          ExecStart = "${lib.getExe attopkgs.strata-wake} gate --config ${gateConfig}";
          Restart = "on-failure";
          RestartSec = 5;
        };
      }
    ];
  };
}
