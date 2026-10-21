{ config, lib, ... }:
let
  cfg = config.modules.traefik;
in
{
  config = lib.mkIf (cfg.enable && cfg.accessLog.enable) {
    systemd.services.traefik.serviceConfig = {
      LogsDirectory = "traefik";
      LogsDirectoryMode = "0700";
      UMask = "0077";
    };
    # Create the file before fail2ban starts, including on a fresh installation.
    systemd.tmpfiles.rules = [
      "d /var/log/traefik 0700 traefik ${config.services.traefik.group} -"
      "f /var/log/traefik/access.log 0600 traefik ${config.services.traefik.group} -"
    ];
    services.logrotate = {
      enable = true;
      settings.traefik-access = {
        files = [ "/var/log/traefik/access.log" ];
        frequency = "daily";
        rotate = cfg.accessLog.rotate;
        missingok = true;
        notifempty = true;
        compress = true;
        delaycompress = true;
        create = "0600 traefik ${config.services.traefik.group}";
        sharedscripts = true;
        # Traefik reopens its access log on USR1; do not copytruncate active writes.
        postrotate = "${config.systemd.package}/bin/systemctl kill --kill-whom=main --signal=USR1 traefik.service || true";
      };
    };
  };
}
