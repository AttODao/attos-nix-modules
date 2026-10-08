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
  web = ps.select config "ollama";
  standalone = !(web.enabled && !web.standalone && web.cfg.webui);
  transport = { inherit standalone; };
  allowedOrigins =
    config.virtualisation.oci-containers.containers.open-terminal.environment.OPEN_TERMINAL_CORS_ALLOWED_ORIGINS;
  uid = ps.require "modules.open-terminal" "uid" cfg.uid;
  gid = ps.require "modules.open-terminal" "gid" cfg.gid;
in
{
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = environmentFile != null && allowedOrigins != "";
        message = "Open Terminal requires a runtime environmentFile and a nonempty CORS origin when enabled.";
      }
    ];

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
      wants = [ (ps.networkUnit transport) ];
      after = [
        (ps.networkUnit transport)
        "open-terminal-prepare.service"
      ];
    };

    virtualisation.oci-containers.containers.open-terminal = {
      image = lib.mkDefault "ghcr.io/open-webui/open-terminal:0.14.0";
      environmentFiles = lib.mkDefault [ environmentFile ];
      environment = {
        OPEN_TERMINAL_CORS_ALLOWED_ORIGINS = lib.mkDefault (
          if web.enabled && web.cfg.webui then
            ps.url web 8080
          else
            throw "Open Terminal: enable a local Open WebUI registry entry or supply the native OCI CORS environment value."
        );
        OPEN_TERMINAL_ENABLE_SYSTEM_PROMPT = lib.mkDefault "true";
        OPEN_TERMINAL_EXECUTE_TIMEOUT = lib.mkDefault "30";
        OPEN_TERMINAL_FILE_BROWSER_ROOT = lib.mkDefault "home";
        OPEN_TERMINAL_INFO = lib.mkDefault "Isolated Open WebUI workspace. No host filesystem or Docker socket is mounted.";
        OPEN_TERMINAL_MAX_SESSIONS = lib.mkDefault "4";
      };
      autoRemoveOnStop = lib.mkDefault false;
      extraOptions = lib.mkDefault [
        "--restart=unless-stopped"
        "--network-alias=open-terminal"
        "--cap-drop=ALL"
        "--cap-add=SETGID"
        "--security-opt=no-new-privileges:true"
        "--pids-limit=256"
        "--memory=4g"
        "--cpus=2"
      ];
      volumes = lib.mkDefault [
        "${workspaceDir}:/home/user"
        "/etc/localtime:/etc/localtime:ro"
      ];
      ports = lib.mkIf standalone (lib.mkDefault [ "127.0.0.1:8001:8000" ]);
      networks = lib.mkDefault [ (ps.network transport) ];
    };
  };
}
