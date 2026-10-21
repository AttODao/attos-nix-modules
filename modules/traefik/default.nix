{ lib, ps, ... }:
let
  inherit (lib) mkOption types;
in
{
  imports = [
    ./nixos.nix
    ./access-log.nix
    ./fail2ban.nix
  ];
  options.modules.traefik = {
    enable = lib.mkEnableOption "shared Traefik gateway generated from public-services";
    accessLog = {
      enable = lib.mkEnableOption "minimal JSON access logs for the gateway";
      rotate = mkOption {
        type = types.ints.positive;
        default = 7;
        description = "Number of daily access log archives retained, in addition to the current file.";
      };
    };
    fail2ban.enable = lib.mkEnableOption "host-wide bans for verified Web login failure signatures (requires accessLog.enable)";
    environmentFile = ps.pathOption "Runtime Cloudflare environment file containing CLOUDFLARE_API_TOKEN; ACME state stays in services.traefik.dataDir.";
    privateNetworks = mkOption {
      type = types.listOf types.nonEmptyStr;
      default = [ ];
      description = "Consumer-owned IP ranges allowed to access private HTTP/TCP services; required when private routes are registered.";
    };
    certificateDomains = mkOption {
      type = types.listOf (
        types.submodule {
          options = {
            main = mkOption {
              type = types.nonEmptyStr;
              description = "Consumer-owned ACME certificate domain.";
            };
            sans = mkOption {
              type = types.listOf types.nonEmptyStr;
              default = [ ];
              description = "Additional names, including wildcard SANs if needed.";
            };
          };
        }
      );
      default = [ ];
      description = "Explicit wildcard certificate requests; empty lets Traefik request certificates for the configured hostname rules.";
    };
    listenServices = mkOption {
      type = types.listOf (types.strMatching "[^[:space:]/]+\\.service");
      default = [ ];
      example = [ "wireguard-wg0.service" ];
      description = "Network setup services pulled in and ordered before Traefik, for listeners bound to addresses those services create.";
    };
  };
}
