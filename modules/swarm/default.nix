{ config, lib, ... }:
let
  ps = import ../public-services/lib.nix { inherit lib; };
  inherit (lib) mkOption types;
in
{
  imports = [ ./nixos.nix ];
  options.modules.swarm = {
    enable = lib.mkEnableOption "shared Docker Swarm initialization and overlay network";
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
      description = "Manager address including port, such as 10.250.0.1:2377; required for a worker.";
    };
    joinTokenFile = ps.pathOption "Decrypted runtime worker join token; the consumer supplies its transport and permissions.";
    tokenOutputFile = mkOption {
      type = ps.absolutePath;
      default = "/run/docker-swarm/worker-token";
      description = "Manager-generated runtime worker token (0600); never placed in the readiness HTTP directory.";
    };
    networkSubnet = mkOption {
      type = types.nullOr types.nonEmptyStr;
      default = null;
      description = "Subnet for the attachable traefik overlay; required for a manager.";
    };
    networkGateway = mkOption {
      type = types.nullOr types.nonEmptyStr;
      default = null;
      description = "Gateway for the traefik overlay; required for a manager.";
    };
    networkReadyUrl = mkOption {
      type = types.nullOr types.nonEmptyStr;
      default = null;
      description = "Manager's nonsecret readiness URL; required for a worker before containers attach to the overlay.";
    };
    readinessAddress = mkOption {
      type = types.nullOr types.nonEmptyStr;
      default = null;
      description = "Optional manager bind address for serving only the overlay readiness marker; firewall access remains consumer-owned.";
    };
    readinessPort = mkOption {
      type = types.port;
      default = 2378;
      description = "Port for the optional nonsecret readiness endpoint.";
    };
  };
}
