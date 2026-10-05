{
  config,
  lib,
  pkgs,
  ...
}:
let
  ps = import ../public-services/lib.nix { inherit lib; };
  cfg = config.modules.cloudflare-ddns;
  settings = pkgs.writeText "cloudflare-ddns.json" (
    builtins.toJSON {
      recordType = "A";
      inherit (cfg)
        records
        ttl
        proxied
        comment
        ;
    }
  );
in
{
  options.modules.cloudflare-ddns = {
    enable = lib.mkEnableOption "shared Cloudflare public IPv4 updates";
    environmentFile = ps.pathOption "Runtime file containing CLOUDFLARE_API_TOKEN and CLOUDFLARE_ZONE_ID.";
    records = lib.mkOption {
      type = lib.types.listOf lib.types.nonEmptyStr;
      default = [ ];
      description = "Consumer-owned fully qualified A-record names, normally the CNAME target domain.";
    };
    ttl = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1;
      description = "Cloudflare TTL; 1 means automatic.";
    };
    proxied = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether Cloudflare proxies these A records.";
    };
    comment = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "managed by attos cloudflare-ddns";
      description = "Ownership marker written to declared records.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.etc."cloudflare/ddns.json".source = settings;
    assertions = [
      {
        assertion = cfg.records != [ ];
        message = "modules.cloudflare-ddns.records must not be empty when enabled.";
      }
    ];
    systemd.services.cloudflare-ddns = {
      description = "Update declared Cloudflare A records with the public IPv4 address";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      restartTriggers = [ settings ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.python3}/bin/python3 ${./sync-dns.py} /etc/cloudflare/ddns.json";
        EnvironmentFile = ps.require "modules.cloudflare-ddns" "environmentFile" cfg.environmentFile;
        DynamicUser = true;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
      };
    };
    systemd.timers.cloudflare-ddns = {
      description = "Periodically update Cloudflare A records";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = lib.mkDefault "2min";
        OnCalendar = lib.mkDefault "*:0/10";
        AccuracySec = lib.mkDefault "1min";
        RandomizedDelaySec = lib.mkDefault "30s";
        Persistent = lib.mkDefault true;
      };
    };
  };
}
