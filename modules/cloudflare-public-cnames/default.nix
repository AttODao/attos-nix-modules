{
  config,
  lib,
  pkgs,
  ...
}:
let
  ps = import ../public-services/lib.nix { inherit lib; };
  cfg = config.modules.cloudflare-public-cnames;
  target = ps.require "modules.cloudflare-public-cnames" "target" cfg.target;
  publicHosts = lib.filterAttrs (
    _: services:
    lib.any (service: (service.enable or false) && !service.private) (lib.attrValues services)
  ) (ps.hosts config);
  records = lib.filter (hostname: hostname != target) (builtins.attrNames publicHosts);
  settings = pkgs.writeText "cloudflare-public-cnames.json" (
    builtins.toJSON {
      recordType = "CNAME";
      inherit target records;
      inherit (cfg) ttl proxied comment;
    }
  );
in
{
  options.modules.cloudflare-public-cnames = {
    enable = lib.mkEnableOption "shared Cloudflare CNAME synchronization from public-services";
    environmentFile = ps.pathOption "Runtime file containing CLOUDFLARE_API_TOKEN and CLOUDFLARE_ZONE_ID.";
    target = lib.mkOption {
      type = lib.types.nullOr lib.types.nonEmptyStr;
      default = null;
      description = "Consumer-owned CNAME target (normally the DDNS A-record domain).";
    };
    ttl = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1;
      description = "Cloudflare TTL; 1 means automatic.";
    };
    proxied = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether Cloudflare proxies declared CNAME records.";
    };
    comment = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "managed by attos public services";
      description = "Ownership marker used for stale record deletion. Supply the old managed comment when migrating existing records.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.etc."cloudflare/public-cnames.json".source = settings;
    systemd.services.cloudflare-public-cnames = {
      description = "Synchronize enabled, nonprivate public-service CNAMEs";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      restartTriggers = [ settings ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.python3}/bin/python3 ${../cloudflare-ddns/sync-dns.py} /etc/cloudflare/public-cnames.json";
        EnvironmentFile =
          ps.require "modules.cloudflare-public-cnames" "environmentFile"
            cfg.environmentFile;
        Restart = "on-failure";
        RestartSec = "5min";
        DynamicUser = true;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
      };
    };
  };
}
