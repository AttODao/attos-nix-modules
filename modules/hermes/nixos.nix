{ config, lib, ... }:
let
  ps = import ../public-services/lib.nix { inherit lib; };
  selected = ps.select config "hermes";
  cfg = selected.cfg;
  dataDir = ps.require "hermes" "dataDir" cfg.dataDir;
  uid = toString (ps.require "hermes" "uid" cfg.uid);
  gid = toString (ps.require "hermes" "gid" cfg.gid);
in
{
  config = lib.mkIf selected.enabled {
    systemd.tmpfiles.settings."10-hermes" = {
      ${dataDir}.d = {
        mode = "0700";
        user = uid;
        group = gid;
      };
      "${dataDir}/workspace".d = {
        mode = "0700";
        user = uid;
        group = gid;
      };
    };

    systemd.services.docker-hermes = {
      unitConfig = {
        RequiresMountsFor = [ dataDir ];
        # Operator-owned config and credentials must exist before first start.
        ConditionPathExists = [
          "${dataDir}/config.yaml"
          "${dataDir}/.env"
        ];
      };
      wants = [ (ps.networkUnit selected) ];
      after = [ (ps.networkUnit selected) ];
    };

    virtualisation.oci-containers.containers.hermes = {
      # GitHub v0.21.6's release receipt names rc.4; Docker's v0.21.6 tag is an older commit.
      # This index pins 818c13be1dc4fd28987e1e881a9408224afd4535, including web/TUI assets.
      image = lib.mkDefault "nousresearch/hermes-agent:rc.4-v0.21.6@sha256:9774f4f39a9bb8c2f68ce728ed5e99ddbad282163be56764afacf88ed952b784";
      ports = lib.mkDefault (lib.optional selected.standalone "127.0.0.1:9119:9119");
      # Official layout: s6 supervises the gateway (which runs cron) and the dashboard.
      cmd = lib.mkDefault [
        "gateway"
        "run"
      ];
      environment = lib.mapAttrs (_: lib.mkDefault) {
        # The official entrypoint remaps its hermes account, then drops privileges.
        HERMES_UID = uid;
        HERMES_GID = gid;
        HERMES_HOME = "/opt/data";
        HOME = "/opt/data";
        XDG_CACHE_HOME = "/opt/data/.cache";
        PYTHONUNBUFFERED = "1";
        HERMES_DASHBOARD = "1";
        HERMES_DASHBOARD_HOST = "0.0.0.0";
        HERMES_DASHBOARD_PORT = "9119";
      };
      # config.yaml, .env, provider credentials, skills and sessions are writable state.
      # A plain list so other modules can add mounts.
      volumes = [ "${dataDir}:/opt/data" ];
      networks = lib.mkDefault [ (ps.network selected) ];
      autoRemoveOnStop = lib.mkDefault false;
      extraOptions = lib.mkDefault [
        "--restart=unless-stopped"
        "--workdir=/opt/data/workspace"
        # Keep s6 as PID 1 (no --init wrapper). Only bootstrap/supervision retains these caps.
        "--cap-drop=ALL"
        "--cap-add=CHOWN"
        "--cap-add=DAC_OVERRIDE"
        "--cap-add=FOWNER"
        "--cap-add=SETGID"
        "--cap-add=SETUID"
        "--cap-add=KILL"
        "--security-opt=no-new-privileges:true"
      ];
    };
  };
}
