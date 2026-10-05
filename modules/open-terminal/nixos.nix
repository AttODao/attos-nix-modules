{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.modules.open-terminal;
  ps = import ../public-services/lib.nix { inherit lib; };
  dataDir = ps.require "modules.open-terminal" "dataDir" cfg.dataDir;
  workspaceDir = "${dataDir}/workspace";
  environmentFile = ps.require "modules.open-terminal" "environmentFile" cfg.environmentFile;
  allowedOrigins = ps.require "modules.open-terminal" "allowedOrigins" cfg.allowedOrigins;
  uid = ps.require "modules.open-terminal" "uid" cfg.uid;
  gid = ps.require "modules.open-terminal" "gid" cfg.gid;
in
{
  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d ${dataDir} 0700 root root -"
      "d ${workspaceDir} 0700 ${toString uid} ${toString gid} -"
    ];

    systemd.services.open-terminal-prepare = {
      unitConfig.RequiresMountsFor = [ dataDir ];
      serviceConfig.Type = "oneshot";
      script = ''
        set -eu
        ${pkgs.coreutils}/bin/install -d -m 0700 -o root -g root ${lib.escapeShellArg dataDir}
        ${pkgs.coreutils}/bin/install -d -m 0700 -o ${toString uid} -g ${toString gid} ${lib.escapeShellArg workspaceDir}
      '';
    };

    systemd.services.docker-open-terminal = {
      unitConfig.RequiresMountsFor = [ dataDir ];
      requires = [ "open-terminal-prepare.service" ];
      wants = [ "docker-network-traefik.service" ];
      after = [
        "docker-network-traefik.service"
        "open-terminal-prepare.service"
      ];
    };

    virtualisation.oci-containers.containers.open-terminal = {
      image = lib.mkDefault "ghcr.io/open-webui/open-terminal:0.14.0";
      environmentFiles = [ environmentFile ];
      environment = {
        OPEN_TERMINAL_CORS_ALLOWED_ORIGINS = allowedOrigins;
        OPEN_TERMINAL_ENABLE_SYSTEM_PROMPT = lib.mkDefault "true";
        OPEN_TERMINAL_EXECUTE_TIMEOUT = lib.mkDefault "30";
        OPEN_TERMINAL_FILE_BROWSER_ROOT = lib.mkDefault "home";
        OPEN_TERMINAL_INFO = lib.mkDefault "Isolated Open WebUI workspace. No host filesystem or Docker socket is mounted.";
        OPEN_TERMINAL_MAX_SESSIONS = lib.mkDefault "4";
      };
      autoRemoveOnStop = false;
      extraOptions = [
        "--restart=unless-stopped"
        "--network-alias=open-terminal"
        "--cap-drop=ALL"
        "--cap-add=SETGID"
        "--security-opt=no-new-privileges:true"
        "--pids-limit=256"
        "--memory=4g"
        "--cpus=2"
      ];
      volumes = [
        "${workspaceDir}:/home/user"
        "/etc/localtime:/etc/localtime:ro"
      ];
      networks = [ "traefik" ];
    };
  };
}
