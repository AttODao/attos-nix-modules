{ lib, ... }:
let
  ps = import ../public-services/lib.nix { inherit lib; };
  inherit (lib) mkOption types;
in
{
  imports = [ ./nixos.nix ];
  options.modules.swarm = {
    enable = lib.mkEnableOption "shared Docker Swarm initialization and encrypted service overlays";
    role = mkOption {
      type = types.nullOr (
        types.enum [
          "manager"
          "worker"
        ]
      );
      default = null;
      description = "Consumer-selected Swarm role; required when enabled.";
    };
    advertiseAddress = mkOption {
      type = types.nullOr types.nonEmptyStr;
      default = null;
      description = "Manager's advertise/data-path address; required for a manager.";
    };
    managerAddress = mkOption {
      type = types.nullOr types.nonEmptyStr;
      default = null;
      description = "Manager IPv4 address, hostname or bracketed IPv6 address, with optional port (for example 10.250.0.1:2377); required for a worker. Readiness uses the same host on readinessPort (default 2378). IPv6 uses hexadecimal groups without a zone ID.";
    };
    joinTokenFile = ps.pathOption "Runtime worker join token; supplied externally or fetched by the opt-in tokenFetch service.";
    tokenOutputFile = mkOption {
      type = ps.absolutePath;
      default = "/run/docker-swarm/worker-token";
      description = "Manager-generated runtime worker token (0600); never placed in the readiness HTTP directory.";
    };
    readinessAddress = mkOption {
      type = types.nullOr types.nonEmptyStr;
      default = null;
      description = "Optional manager bind address for overlay readiness and opt-in restricted token transport; firewall access remains consumer-owned.";
    };
    readinessPort = mkOption {
      type = types.ints.between 1 65535;
      default = 2378;
      description = "Manager HTTP listener port and worker readiness port.";
    };
    tokenTransport = {
      enable = lib.mkEnableOption "restricted plaintext HTTP worker-token transport on the readiness listener";
      allowedAddresses = mkOption {
        type = types.listOf types.nonEmptyStr;
        default = [ ];
        description = "Exact source IP addresses allowed to fetch the token and readiness marker. Required when tokenTransport is enabled. This is not authenticated encryption.";
      };
    };
    tokenFetch = {
      enable = lib.mkEnableOption "automatic atomic worker-token fetch before Swarm join";
      url = mkOption {
        type = types.nullOr (
          types.strMatching "http://([a-zA-Z0-9.-]+|[[][0-9a-fA-F:]+[]])(:[0-9]+)?/worker-token"
        );
        default = null;
        description = "Explicit plaintext private-link token endpoint, for example http://10.250.0.1:2378/worker-token. Required when tokenFetch is enabled.";
      };
      sourceAddress = mkOption {
        type = types.nullOr types.nonEmptyStr;
        default = null;
        description = "Optional local source address passed to curl --interface; the consumer owns host addressing.";
      };
    };
  };
}
