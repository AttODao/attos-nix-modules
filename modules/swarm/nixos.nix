{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.modules.swarm;
  ps = import ../public-services/lib.nix { inherit lib; };
  required = field: ps.require "modules.swarm" field cfg.${field};
  managerHost =
    let
      address = required "managerAddress";
      parts = builtins.match "([a-zA-Z0-9.-]+|[[][0-9a-fA-F:]+[]])(:([0-9]+))?" address;
      host = builtins.head parts;
      port = builtins.elemAt parts 2;
      ipv6 = lib.removeSuffix "]" (lib.removePrefix "[" host);
      validHost =
        if lib.hasPrefix "[" host then
          lib.all (piece: builtins.stringLength piece <= 4) (lib.splitString ":" ipv6)
          && (builtins.tryEval (builtins.deepSeq (lib.network.ipv6.fromString ipv6) true)).success
        else if builtins.match "[0-9.]+" host != null then
          builtins.match "[0-9]{1,3}([.][0-9]{1,3}){3}" host != null
          && lib.all (octet: builtins.match "0|[1-9][0-9]{0,2}" octet != null && lib.toInt octet <= 255) (
            lib.splitString "." host
          )
        else
          builtins.stringLength host <= 253
          &&
            builtins.match "[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?([.][a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*[.]?" host
            != null;
      validPort =
        port == null || (builtins.match "[1-9][0-9]{0,4}" port != null && lib.toInt port <= 65535);
    in
    if parts != null && validHost && validPort then
      host
    else
      throw "modules.swarm.managerAddress must be an IPv4 address, hostname or bracketed hexadecimal IPv6 address, with an optional port from 1 to 65535.";
  managerAddress = builtins.seq managerHost (required "managerAddress");
  networkReadyUrl = "http://${managerHost}:2378/traefik-network-ready";
  swarm = pkgs.writeShellApplication {
    name = "attos-swarm";
    runtimeInputs = [
      pkgs.docker
      pkgs.coreutils
      pkgs.curl
    ];
    text = builtins.readFile ./swarm.sh;
  };
  manager = cfg.role == "manager";
  joinUnit = if manager then "docker-swarm-init" else "docker-swarm-join";
  marker = "/run/docker-swarm-network-ready/traefik-network-ready";
in
{
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        modules.docker.enable = true;
        assertions = [
          {
            assertion = cfg.role != null;
            message = "modules.swarm.role must be manager or worker when enabled.";
          }
        ];
        systemd.services.${joinUnit} = {
          description = "Initialize or join the consumer-selected Docker Swarm";
          wantedBy = [ "multi-user.target" ];
          after = [
            "docker.service"
            "docker.socket"
            "network-online.target"
          ];
          wants = [ "network-online.target" ];
          requires = [ "docker.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            UMask = "0077";
            ExecStart =
              if manager then
                "${swarm}/bin/attos-swarm manager ${
                  lib.escapeShellArgs [
                    (required "advertiseAddress")
                    cfg.tokenOutputFile
                  ]
                }"
              else
                "${swarm}/bin/attos-swarm worker ${lib.escapeShellArg managerAddress} %d/join-token";
          }
          // lib.optionalAttrs (!manager) {
            LoadCredential = [ "join-token:${required "joinTokenFile"}" ];
          };
        };
        systemd.services.docker-network-traefik = {
          description = "Ensure the attachable traefik overlay is ready";
          wantedBy = [ "multi-user.target" ];
          after = [
            "${joinUnit}.service"
            "docker.service"
            "docker.socket"
          ];
          requires = [ "${joinUnit}.service" ];
          restartIfChanged = false;
          stopIfChanged = false;
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart =
              if manager then
                "${swarm}/bin/attos-swarm network ${
                  lib.escapeShellArgs [
                    (required "networkSubnet")
                    (required "networkGateway")
                    marker
                  ]
                }"
              else
                "${swarm}/bin/attos-swarm wait ${lib.escapeShellArg networkReadyUrl}";
          };
        };
      }
      (lib.mkIf (manager && cfg.readinessAddress != null) {
        systemd.tmpfiles.rules = [ "d /run/docker-swarm-network-ready 0755 root root -" ];
        systemd.services.docker-swarm-network-server = {
          description = "Serve the nonsecret overlay readiness marker (not the join token)";
          wantedBy = [ "multi-user.target" ];
          after = [ "docker-network-traefik.service" ];
          requires = [ "docker-network-traefik.service" ];
          serviceConfig = {
            ExecStart = "${pkgs.python3}/bin/python3 ${./readiness-server.py} ${
              lib.escapeShellArgs [
                cfg.readinessAddress
                "2378"
                marker
              ]
            }";
            DynamicUser = true;
            Restart = "on-failure";
            RestartSec = "2s";
            NoNewPrivileges = true;
            ProtectSystem = "strict";
            ProtectHome = true;
          };
        };
      })
    ]
  );
}
