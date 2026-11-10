{
  config,
  lib,
  ps,
  ...
}:
let
  cfg = config.modules.cloudflare-ddns;
in
{
  options.modules.cloudflare-ddns = {
    enable = lib.mkEnableOption "shared Cloudflare public IPv4 updates";
    environmentFile = ps.pathOption "Runtime file containing CLOUDFLARE_API_TOKEN.";
    records = lib.mkOption {
      type = lib.types.listOf lib.types.nonEmptyStr;
      default = [ ];
      description = "Fully qualified A-record names to keep at the public IPv4 address, normally the target of modules.cloudflare-public-cnames; must not be empty when enabled. TTL and proxying use the standard services.cloudflare-ddns options.";
    };
    comment = lib.mkOption {
      type = lib.types.nonEmptyStr;
      default = "managed by attos cloudflare-ddns";
      description = "Comment written to the declared records (services.cloudflare-ddns.recordComment).";
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
      recordComment = lib.mkDefault cfg.comment;
    };
  };
}
