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
  networkReadyUrl = "http://${managerHost}:${toString cfg.readinessPort}/networks-ready";
  containerNetworks = lib.unique (
    lib.concatMap (container: lib.filter (lib.hasPrefix "backend-") container.networks) (
      lib.attrValues config.virtualisation.oci-containers.containers
    )
  );
  # The manager provisions remote owners too; workers wait only for their attachments.
  networks = lib.unique (
    containerNetworks
    ++ lib.optionals manager (
      ps.backendNetworks config
      ++
        lib.optional (lib.any (route: route.service == "ollama" && route.cfg.deploy) (ps.routes config))
          (
            ps.network {
              standalone = false;
              service = "open-terminal";
            }
          )
    )
  );
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
  marker = "/run/docker-swarm-network-ready/networks-ready";
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
          {
            assertion =
              !cfg.tokenTransport.enable
              || (manager && cfg.readinessAddress != null && cfg.tokenTransport.allowedAddresses != [ ]);
            message = "modules.swarm.tokenTransport requires a manager, readinessAddress and nonempty allowedAddresses.";
          }
          {
            assertion = !cfg.tokenFetch.enable || (!manager && cfg.tokenFetch.url != null);
            message = "modules.swarm.tokenFetch requires a worker and an explicit private-link HTTP url.";
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
        systemd.services.docker-swarm-networks = {
          description = "Ensure encrypted service overlays are ready";
          wantedBy = [ "multi-user.target" ];
          after = [
            "${joinUnit}.service"
            "docker.service"
            "docker.socket"
          ];
          requires = [ "${joinUnit}.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            ExecStart =
              if manager then
                "${swarm}/bin/attos-swarm network ${lib.escapeShellArgs ([ marker ] ++ networks)}"
              else
                "${swarm}/bin/attos-swarm wait ${lib.escapeShellArg networkReadyUrl}";
          };
        };
      }
      {
        systemd.services = lib.genAttrs (map (network: "docker-network-${network}") networks) (
          unit:
          let
            network = lib.removePrefix "docker-network-" unit;
          in
          {
            description = "Wait for the ${network} encrypted overlay";
            requires = [ "${joinUnit}.service" ] ++ lib.optional manager "docker-swarm-networks.service";
            after = [ "${joinUnit}.service" ] ++ lib.optional manager "docker-swarm-networks.service";
            serviceConfig = {
              Type = "oneshot";
              RemainAfterExit = true;
              ExecStart =
                if manager then
                  "${pkgs.coreutils}/bin/test -f ${marker}/${network}"
                else
                  "${swarm}/bin/attos-swarm wait ${
                    lib.escapeShellArgs [
                      "${networkReadyUrl}/${network}"
                      network
                    ]
                  }";
            };
          }
        );
      }
      {
        # Recheck on every container start: oneshot units can remain active after prune.
        systemd.services =
          lib.mapAttrs'
            (
              name: container:
              lib.nameValuePair container.serviceName {
                preStart = lib.mkBefore (
                  if manager then
                    "${swarm}/bin/attos-swarm network ${lib.escapeShellArgs ([ marker ] ++ networks)}"
                  else
                    lib.concatMapStringsSep "\n" (
                      network:
                      "${swarm}/bin/attos-swarm wait ${
                        lib.escapeShellArgs [
                          "${networkReadyUrl}/${network}"
                          network
                        ]
                      }"
                    ) (lib.filter (lib.hasPrefix "backend-") container.networks)
                );
              }
            )
            (
              lib.filterAttrs (
                _: c: lib.any (lib.hasPrefix "backend-") c.networks
              ) config.virtualisation.oci-containers.containers
            );
      }
      (lib.mkIf (!manager && cfg.tokenFetch.enable) {
        systemd.services.docker-swarm-token-fetch = {
          description = "Fetch a private-link Swarm worker token atomically";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            RuntimeDirectory = "docker-swarm";
            RuntimeDirectoryMode = "0700";
            UMask = "0077";
            ExecStart = "${swarm}/bin/attos-swarm fetch ${
              lib.escapeShellArgs [
                (ps.require "modules.swarm.tokenFetch" "url" cfg.tokenFetch.url)
                (if cfg.tokenFetch.sourceAddress == null then "" else cfg.tokenFetch.sourceAddress)
                (required "joinTokenFile")
              ]
            }";
          };
        };
        # Fetch before systemd snapshots LoadCredential, including already joined workers.
        systemd.services.docker-swarm-join = {
          requires = [ "docker-swarm-token-fetch.service" ];
          after = [ "docker-swarm-token-fetch.service" ];
        };
      })
      (lib.mkIf (manager && cfg.readinessAddress != null) {
        systemd.tmpfiles.rules = [ "d /run/docker-swarm-network-ready 0755 root root -" ];
        systemd.services.docker-swarm-network-server = {
          description =
            if cfg.tokenTransport.enable then
              "Serve restricted private-link Swarm token and readiness"
            else
              "Serve the nonsecret overlay readiness marker (not the join token)";
          wantedBy = [ "multi-user.target" ];
          after = [
            "docker-swarm-networks.service"
          ]
          ++ lib.optional cfg.tokenTransport.enable "docker-swarm-init.service";
          requires = [
            "docker-swarm-networks.service"
          ]
          ++ lib.optional cfg.tokenTransport.enable "docker-swarm-init.service";
          serviceConfig = {
            ExecStart =
              if cfg.tokenTransport.enable then
                "${pkgs.python3}/bin/python3 ${./token-server.py} ${
                  lib.escapeShellArgs [
                    cfg.readinessAddress
                    (toString cfg.readinessPort)
                  ]
                } %d/worker-token ${lib.escapeShellArgs ([ marker ] ++ cfg.tokenTransport.allowedAddresses)}"
              else
                "${pkgs.python3}/bin/python3 ${./readiness-server.py} ${
                  lib.escapeShellArgs [
                    cfg.readinessAddress
                    (toString cfg.readinessPort)
                    marker
                  ]
                }";
            DynamicUser = true;
            Restart = "on-failure";
            RestartSec = "2s";
            NoNewPrivileges = true;
            ProtectSystem = "strict";
            ProtectHome = true;
          }
          // lib.optionalAttrs cfg.tokenTransport.enable {
            LoadCredential = [ "worker-token:${cfg.tokenOutputFile}" ];
          };
        };
      })
    ]
  );
}
