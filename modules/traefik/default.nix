{ lib, ... }:
let
  ps = import ../public-services/lib.nix { inherit lib; };
  inherit (lib) mkOption types;
in
{
  imports = [ ./nixos.nix ];
  options.modules.traefik = {
    enable = lib.mkEnableOption "shared Traefik gateway generated from public-services";
    dataDir = ps.pathOption "Persistent Traefik directory containing acme certificate state.";
    environmentFile = ps.pathOption "Runtime Cloudflare environment file containing CLOUDFLARE_API_TOKEN.";
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
    acmeEmail = mkOption {
      type = types.nullOr types.nonEmptyStr;
      default = null;
      description = "Optional consumer-owned ACME contact email.";
    };
  };
}
