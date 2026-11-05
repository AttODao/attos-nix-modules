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
    cancelOnLocalLogin = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Cancel a shutdown that is still waiting for remote sessions when someone logs in locally again after the local sessions were ended, so the machine does not power off under the new session.";
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
        # State of one shutdown request: when it was seen, the local sessions open at that time,
        # and whether those were ended.
        requested_at=""
        known_ids=" "
        terminated=0
        preparing() {
          [ "$(busctl get-property org.freedesktop.login1 /org/freedesktop/login1 \
            org.freedesktop.login1.Manager PreparingForShutdown 2>/dev/null)" = "b true" ]
        }
        cancel_shutdown() {
          # logind has no call that drops a delayed PowerOff/Reboot, but cancelling a scheduled
          # shutdown also drops the pending delayed action. Schedule a dry-run one a year ahead
          # (it never powers off) and cancel it at once.
          local at=$((($(date +%s) + 31536000) * 1000000))
          busctl call org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager \
            ScheduleShutdown st dry-poweroff "$at" &&
            busctl call org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager \
              CancelScheduledShutdown >/dev/null
        }
        forget_request() {
          requested_at=""
          known_ids=" "
          terminated=0
        }
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
            props=$(loginctl show-session "$id" -p Class -p Remote -p State 2>/dev/null) || continue
            case "$props" in
              *Class=user*) ;;
              *) continue ;;
            esac
            case "$props" in
              *Remote=yes*) remote=1 ;;
              *State=closing*) ;;
              *) local_sessions+=("$id") ;;
            esac
          done
          if [ "$remote" = 1 ]; then
            if [ -z "$lock_pid" ]; then
              systemd-inhibit --what=shutdown --mode=delay --who=shutdown-hold \
                --why="Remote sessions (SSH, Hermes Bot Screen) are still running" sleep infinity &
              lock_pid=$!
            fi
            if preparing; then
              now=$(date +%s)
              if [ -z "$requested_at" ]; then
                requested_at=$now
                known_ids=" ''${local_sessions[*]} "
              fi
              new_local=0
              for id in "''${local_sessions[@]}"; do
                case "$known_ids" in
                  *" $id "*) ;;
                  *) new_local=1 ;;
                esac
              done
              if [ "$new_local" = 1 ] && ${lib.boolToString cfg.cancelOnLocalLogin}; then
                # Someone logged in again while the shutdown still waits: keep the machine running.
                if cancel_shutdown && ! preparing; then
                  echo "local login while the shutdown waited for remote sessions: shutdown cancelled"
                  forget_request
                else
                  echo "local login while the shutdown waited, but cancelling it failed" >&2
                  known_ids=" ''${local_sessions[*]} "
                fi
              elif [ "$terminated" = 0 ] && [ $((now - requested_at)) -ge ${toString cfg.localSessionGrace} ]; then
                # After the grace period, end the local sessions so the desktop is not left open
                # while waiting.
                for id in "''${local_sessions[@]}"; do
                  loginctl terminate-session "$id" || true
                done
                terminated=1
              fi
            else
              forget_request
            fi
          else
            release
            forget_request
          fi
          sleep 5
        done
      '';
    };
  };
}
