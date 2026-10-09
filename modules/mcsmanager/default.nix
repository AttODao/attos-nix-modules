{ config, lib, ... }:
let
  ps = import ../public-services/lib.nix { inherit lib; };
  nullableName =
    description:
    lib.mkOption {
      type = lib.types.nullOr lib.types.nonEmptyStr;
      default = null;
      inherit description;
    };
  upstream =
    description:
    lib.mkOption {
      type = lib.types.nullOr (lib.types.strMatching "https?://[^[:space:]]+");
      default = null;
      inherit description;
    };
in
{
  imports = [ ./nixos.nix ];
  options.modules = ps.moduleOptions "mcsmanager" (
    ps.common "MCSManager game management"
    // {
      private = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Restrict management UI/API and daemon HTTP/WebSocket to private networks. Does not restrict game ports.";
      };
      dataDir = ps.pathOption "Consumer-owned state root; web and daemon state are kept in separate subdirectories.";
      webUser = nullableName "Existing non-root account running the management web service.";
      daemonUser = nullableName "Existing non-root account running the daemon and native game processes; must differ from webUser.";
      group = nullableName "Existing non-Docker group used by both service accounts (state files remain private to their owner).";
      daemonKeyFile = ps.pathOption "Runtime plaintext daemon authentication key, loaded with systemd credentials. Required unless generateDaemonKey is true. Never supply a Nix path literal or key contents.";
      generateDaemonKey = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Generate dataDir/daemon-key atomically on first startup, privately as root; never replace an existing key. daemonKeyFile must be null or that same path. False uses a consumer-supplied runtime credential.";
      };
      initialAdminFile = ps.pathOption "Optional runtime JSON initial administrator (userName and bcrypt passWord hash); only used when no users exist. Null uses the official initialization UI over the private management route.";
      listenAddress = lib.mkOption {
        type = lib.types.nonEmptyStr;
        default = "127.0.0.1";
        description = "Management web/daemon bind address. Public deployments may select a gateway-only backend interface; consumer firewall must deny direct non-gateway access. Standalone remains loopback-only.";
      };
      webPort = lib.mkOption {
        type = lib.types.port;
        default = 23333;
        description = "Management web HTTP listener; never opened by this module.";
      };
      daemonPort = lib.mkOption {
        type = lib.types.port;
        default = 24444;
        description = "Daemon HTTP/WebSocket listener under /daemon/; never opened by this module.";
      };
      backendUrl = upstream "Management web upstream reachable by the HTTPS gateway.";
      daemonBackendUrl = upstream "Daemon upstream reachable by the same HTTPS gateway; route /daemon/ without stripping its prefix.";
      backendAddress = nullableName "Native game backend address reachable by the gateway; independent of management visibility.";
      tcpPorts = lib.mkOption {
        type = lib.types.listOf lib.types.port;
        default = [ ];
        description = "Game TCP ports forwarded independently by the gateway; private applies only to management. Does not open the host firewall or choose game listeners.";
      };
      udpPorts = lib.mkOption {
        type = lib.types.listOf lib.types.port;
        default = [ ];
        description = "Game UDP ports forwarded independently by the gateway; private applies only to management. Does not open the host firewall or choose game listeners.";
      };
    }
  );
}
