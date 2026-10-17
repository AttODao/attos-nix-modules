{ config, lib, ... }:
let
  ps = import ../public-services/lib.nix { inherit lib; };
  cfg = config.modules.cloudflare-ddns;
in
{
  options.modules.cloudflare-ddns = {
    enable = lib.mkEnableOption "shared Cloudflare public IPv4 updates";
    environmentFile = ps.pathOption "Runtime file containing CLOUDFLARE_API_TOKEN.";
    records = lib.mkOption {
      type = lib.types.listOf lib.types.nonEmptyStr;
      default = [ ];
      description = "Consumer-owned fully qualified A-record names, normally the CNAME target domain.";
    };
    ttl = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1;
      description = "Cloudflare TTL; 1 means automatic, otherwise 30-86400.";
    };
    proxied = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether Cloudflare proxies these A records.";
    };
    comment = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "managed by attos cloudflare-ddns";
      description = "Comment written to declared records.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.records != [ ];
        message = "modules.cloudflare-ddns.records must not be empty when enabled.";
      }
    ];
    services.cloudflare-ddns = {
      enable = true;
      credentialsFile = ps.require "modules.cloudflare-ddns" "environmentFile" cfg.environmentFile;
      domains = cfg.records;
      provider.ipv6 = lib.mkDefault "none";
      ttl = lib.mkDefault cfg.ttl;
      proxied = lib.mkDefault (lib.boolToString cfg.proxied);
      recordComment = lib.mkDefault cfg.comment;
    };
  };
}
