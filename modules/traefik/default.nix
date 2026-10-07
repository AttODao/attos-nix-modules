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
    publishedPortRanges = mkOption {
      type = types.nullOr (
        types.listOf (
          types.submodule (
            { config, ... }: {
              options = {
                start = mkOption {
                  type = types.ints.between 1 65535;
                  description = "First port published identically on the host and container.";
                };
                end = mkOption {
                  type = types.ints.between 1 65535;
                  default = config.start;
                  description = "Last port in the inclusive range; defaults to start.";
                };
                protocol = mkOption {
                  type = types.enum [
                    "tcp"
                    "udp"
                  ];
                  default = "tcp";
                  description = "Transport published by this range.";
                };
              };
            }
          )
        )
      );
      default = null;
      description = "Ordered Docker publication ranges, or null to publish individual generated listeners. Explicit ranges must cover exactly the generated listener ports, without overlaps or additional exposure.";
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
  };
}
