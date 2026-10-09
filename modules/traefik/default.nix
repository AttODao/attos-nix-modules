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
    nativeBackendNetwork = mkOption {
      default = null;
      description = "Optional dedicated local Docker bridge for gateway access to native backends. Traefik receives a fixed IPv4 address and prefers this bridge for egress. Consumer owns addresses and source/interface firewall rules; no backend ports are opened.";
      type = types.nullOr (
        types.submodule {
          options = {
            name = mkOption {
              type = types.strMatching "[a-zA-Z0-9][a-zA-Z0-9_.-]*";
              default = "traefik-native";
              description = "Dedicated Docker network name.";
            };
            interface = mkOption {
              type = types.strMatching "[a-zA-Z0-9_.-]{1,15}";
              default = "br-traefik";
              description = "Linux bridge interface used by consumer firewall rules.";
            };
            subnet = mkOption {
              type = types.strMatching "([0-9]{1,3}\\.){3}[0-9]{1,3}/[0-9]{1,2}";
              description = "Consumer-reserved IPv4 CIDR; Docker validates address ranges and rejects overlap.";
            };
            gateway = mkOption {
              type = types.strMatching "([0-9]{1,3}\\.){3}[0-9]{1,3}";
              description = "Host-side IPv4 gateway on this bridge.";
            };
            address = mkOption {
              type = types.strMatching "([0-9]{1,3}\\.){3}[0-9]{1,3}";
              description = "Fixed Traefik container IPv4 address in the subnet, distinct from gateway.";
            };
          };
        }
      );
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
