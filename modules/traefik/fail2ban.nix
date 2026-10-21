{
  config,
  lib,
  ps,
  ...
}:
let
  cfg = config.modules.traefik;
  # Only signatures verified against upstream implementations. Sources and exclusions
  # are documented in the module-traefik wiki page. Never count general 401/403s.
  signatures = {
    forgejo = {
      path = "/user/login";
      status = 200;
    };
    immich = {
      path = "/api/auth/login";
      status = 401;
    };
    jellyfin = {
      path = "(?i:/Users/AuthenticateByName)";
      status = 401;
    };
    attos-hoyo-dashboard = {
      path = "/api/v1/auth/login";
      status = 401;
    };
  };
  routes = lib.filter (route: builtins.hasAttr route.service signatures) (ps.routes config);
  # Traefik uses logrus.JSONFormatter -> encoding/json: map keys are sorted.
  # Keep a fully anchored prefix and exact field boundaries: attacker-controlled
  # Host/path/header values must never inject the address to ban. Logrus adds time,
  # level and msg even with fields.defaultMode=drop. Query parameters are dropped.
  failregex = lib.concatMapStringsSep "\n" (
    route:
    let
      signature = signatures.${route.service};
      hostname = lib.escapeRegex route.hostname;
    in
    ''^\{"ClientHost":"<ADDR>","DownstreamStatus":${toString signature.status},"RequestHost":"${hostname}","RequestMethod":"POST","RequestPath":"${signature.path}","RouterName":"${hostname}@file",.*\}$''
  ) routes;
in
{
  config = lib.mkIf (cfg.enable && cfg.fail2ban.enable) {
    assertions = [
      {
        assertion = cfg.accessLog.enable;
        message = "modules.traefik.fail2ban.enable requires modules.traefik.accessLog.enable.";
      }
    ];
    # NixOS's base unit tracks jail.local, but not custom filter contents.
    systemd.services.fail2ban.restartTriggers = [
      config.environment.etc."fail2ban/filter.d/traefik-auth.conf".source
    ];
    services.fail2ban = {
      enable = true;
      jails.traefik-auth = {
        # No supported public route means no matches and no active jail.
        enabled = lib.mkDefault (routes != [ ]);
        filter.Definition = {
          inherit failregex;
          ignoreregex = "";
          datepattern = ''"time":"%%Y-%%m-%%dT%%H:%%M:%%S%%z"'';
        };
        settings = lib.mapAttrs (_: lib.mkDefault) {
          backend = "polling";
          logpath = "/var/log/traefik/access.log";
          usedns = "no";
          protocol = "all";
          maxretry = 10;
          findtime = "10m";
          bantime = "1h";
          "bantime.increment" = true;
          "bantime.maxtime" = "1d";
          # Use NixOS's backend-aware allports action, including every Traefik listener.
          banaction = config.services.fail2ban.banaction-allports;
        };
      };
    };
  };
}
