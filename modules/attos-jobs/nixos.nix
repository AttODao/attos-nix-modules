{
  config,
  lib,
  pkgs,
  attopkgs,
  ...
}:
let
  cfg = config.modules.attos-jobs;
  pkg = attopkgs.attos-jobs;
  heavy = config.modules.heavy.enable;
  statusFile = "/run/attos-jobs/status.json";
  agentConfig = {
    inherit statusFile;
    socket = "/run/attos-jobs/control.sock";
    socketGroup = cfg.socketGroup;
    pauseFile = "/run/attos-jobs/paused";
    intervalSec = 5;
    stopTimeoutSec = 10;
    minSessionAgeSec = 15;
    heavy =
      if heavy then
        {
          lockFile = "/run/heavy/lock";
          ownerFile = "/run/heavy/owner";
          pauseFile = "/run/heavy/paused";
        }
      else
        null;
    docker = lib.optionalString config.virtualisation.docker.enable "${config.virtualisation.docker.package}/bin/docker";
    # forgejo-runner names job containers FORGEJO-ACTIONS-TASK-<task>_WORKFLOW-<workflow>_JOB-<job>.
    ciNamePatterns = [ "^(FORGEJO|GITEA)-ACTIONS-TASK-" ];
    inherit (cfg) units pauseUnits originNames;
    systemctl = "${config.systemd.package}/bin/systemctl";
    loginctl = "${config.systemd.package}/bin/loginctl";
    busctl = "${config.systemd.package}/bin/busctl";
    cgroupRoot = "/sys/fs/cgroup";
    procRoot = "/proc";
  };
  plugin = pkgs.runCommand "attos-jobs-noctalia-plugin" { } ''
    mkdir -p $out/jobs
    cp ${./noctalia/jobs}/* $out/jobs/
    cat > $out/jobs/config.luau <<'EOF'
    return {
      bin = ${builtins.toJSON "${pkg}/bin/attos-jobs"},
      status = ${builtins.toJSON statusFile},
    }
    EOF
  '';
in
{
  config = lib.mkMerge [
    { modules.attos-jobs.noctalia.plugin = plugin; }
    (lib.mkIf cfg.enable {
      environment.systemPackages = [ pkg ];
      environment.etc."attos-jobs/config.json".text = builtins.toJSON agentConfig;

      systemd.services.attos-jobs-agent = {
        description = "attos-jobs agent: list and stop remote work";
        wantedBy = [ "multi-user.target" ];
        after = [
          "systemd-logind.service"
        ]
        ++ lib.optional config.virtualisation.docker.enable "docker.service";
        restartTriggers = [ config.environment.etc."attos-jobs/config.json".source ];
        serviceConfig = {
          ExecStart = "${pkg}/bin/attos-jobs agent";
          Restart = "always";
          RestartSec = 5;
          # The pause flag lives here and must survive agent restarts (switches); a reboot clears it.
          RuntimeDirectory = "attos-jobs";
          RuntimeDirectoryMode = "0755";
          RuntimeDirectoryPreserve = true;
          # Root: it signals other users' processes, kills cgroups, talks to Docker and logind.
          ProtectSystem = "strict";
          ReadWritePaths = [ "/run/attos-jobs" ] ++ lib.optional heavy "/run/heavy";
          ProtectHome = true;
          PrivateTmp = true;
          NoNewPrivileges = true;
          RestrictAddressFamilies = [ "AF_UNIX" ];
        };
      };
    })
  ];
}
