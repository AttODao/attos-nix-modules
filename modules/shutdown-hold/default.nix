{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.modules.shutdown-hold;
in
{
  options.modules.shutdown-hold = {
    enable = lib.mkEnableOption "delaying shutdown and reboot requested through logind while remote (SSH) user sessions exist, including sessions kept by processes they left running such as a Hermes Bot Screen; local sessions are ended meanwhile so the desktop is not left open";
    maxDelay = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "12h";
      example = "infinity";
      description = "Upper bound of the wait, written to logind's InhibitDelayMaxSec (which also bounds every other delay inhibitor, such as screen lockers before sleep).";
    };
    localSessionGrace = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 0;
      example = 120;
      description = "Seconds the local sessions stay open after a shutdown request before they are ended, so the user can still stop the remote work (e.g. from the attos-jobs panel). 0 ends them at once.";
    };
  };
  config = lib.mkIf cfg.enable {
    services.logind.settings.Login.InhibitDelayMaxSec = cfg.maxDelay;
    systemd.services.systemd-logind.reloadTriggers = [
      config.environment.etc."systemd/logind.conf".source
    ];
    systemd.services.shutdown-hold = {
      description = "Delay shutdown while remote sessions run";
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-logind.service" ];
      path = with pkgs; [
        systemd
        procps
        gawk
        coreutils
      ];
      serviceConfig = {
        Restart = "always";
        RestartSec = 5;
      };
      script = ''
        set -u
        lock_pid=""
        terminated=0
        requested_at=""
        release() {
          if [ -n "$lock_pid" ]; then
            # Ending systemd-inhibit's child makes it exit and drop the delay lock.
            pkill -P "$lock_pid" || true
            wait "$lock_pid" 2>/dev/null || true
            lock_pid=""
          fi
        }
        trap 'release; exit 0' TERM INT
        while :; do
          remote=0
          local_sessions=()
          for id in $(loginctl list-sessions --no-legend | awk '{print $1}'); do
            props=$(loginctl show-session "$id" -p Class -p Remote 2>/dev/null) || continue
            case "$props" in
              *Class=user*) ;;
              *) continue ;;
            esac
            case "$props" in
              *Remote=yes*) remote=1 ;;
              *) local_sessions+=("$id") ;;
            esac
          done
          if [ "$remote" = 1 ]; then
            if [ -z "$lock_pid" ]; then
              systemd-inhibit --what=shutdown --mode=delay --who=shutdown-hold \
                --why="Remote sessions (SSH, Hermes Bot Screen) are still running" sleep infinity &
              lock_pid=$!
            fi
            if [ "$terminated" = 0 ] && [ "$(busctl get-property org.freedesktop.login1 /org/freedesktop/login1 \
              org.freedesktop.login1.Manager PreparingForShutdown 2>/dev/null)" = "b true" ]; then
              now=$(date +%s)
              requested_at=''${requested_at:-$now}
              # Shutdown was requested: after the grace period, end local sessions so the desktop
              # is not left open while waiting.
              if [ $((now - requested_at)) -ge ${toString cfg.localSessionGrace} ]; then
                for id in "''${local_sessions[@]}"; do
                  loginctl terminate-session "$id" || true
                done
                terminated=1
              fi
            fi
          else
            release
          fi
          sleep 5
        done
      '';
    };
  };
}
