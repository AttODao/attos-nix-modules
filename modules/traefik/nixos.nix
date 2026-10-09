{
  config,
  lib,
  pkgs,
  ...
}:
let
  ps = import ../public-services/lib.nix { inherit lib; };
  cfg = config.modules.traefik;
  root = ps.require "modules.traefik" "dataDir" cfg.dataDir;
  environmentFile = ps.require "modules.traefik" "environmentFile" cfg.environmentFile;
  routes = ps.routes config;
  games = ps.entries config "mcsmanager";
  networks = ps.backendNetworks config;
  native = cfg.nativeBackendNetwork;
  nativeUnits = lib.optional (native != null) "docker-network-${native.name}.service";
  networkUnits = map (network: "docker-network-${network}.service") networks ++ nativeUnits;
  docker = "${config.virtualisation.docker.package}/bin/docker --host=unix:///run/docker.sock";
  ensureNativeNetwork = lib.optionalString (native != null) ''
    if ! ${docker} network inspect ${lib.escapeShellArg native.name} >/dev/null 2>&1; then
      ${docker} network create --driver bridge \
        --subnet ${lib.escapeShellArg native.subnet} --gateway ${lib.escapeShellArg native.gateway} \
        --opt ${lib.escapeShellArg "com.docker.network.bridge.name=${native.interface}"} ${lib.escapeShellArg native.name} >/dev/null
    fi
    ${docker} network inspect ${lib.escapeShellArg native.name} |
      ${pkgs.jq}/bin/jq -e ${lib.escapeShellArg ''
        length == 1 and .[0].Driver == "bridge" and .[0].Scope == "local"
                and .[0].Options["com.docker.network.bridge.name"] == ${builtins.toJSON native.interface}
                and .[0].IPAM.Config == ${
                  builtins.toJSON [
                    {
                      Subnet = native.subnet;
                      Gateway = native.gateway;
                    }
                  ]
                }''} >/dev/null
  '';
  mails = ps.entries config "mailserver";
  game = if games == [ ] then null else builtins.head games;
  mail = if mails == [ ] then null else builtins.head mails;
  tcp =
    (lib.optionals (game != null) (
      map (port: {
        name = "minecraft-${toString port}";
        inherit port;
        address = "${ps.require "mcsmanager" "backendAddress" game.cfg.backendAddress}:${toString port}";
        private = false;
      }) game.cfg.tcpPorts
    ))
    ++ (lib.optionals (mail != null) (
      map (port: {
        name = "mail-${toString port}";
        inherit port;
        address = "${ps.require "mailserver" "backendAddress" mail.cfg.backendAddress}:${toString port}";
        private = mail.cfg.private;
      }) mail.cfg.tcpPorts
    ));
  udp = lib.optionals (game != null) (
    map (port: {
      name = "minecraft-bedrock-${toString port}";
      inherit port;
      address = "${ps.require "mcsmanager" "backendAddress" game.cfg.backendAddress}:${toString port}";
    }) game.cfg.udpPorts
  );
  byName =
    entries: value:
    builtins.listToAttrs (
      map (entry: {
        name = entry.name;
        value = value entry;
      }) entries
    );
  privateEnabled =
    games != [ ] || lib.any (route: route.cfg.private) routes || lib.any (entry: entry.private) tcp;
  tls = {
    certResolver = "letsencrypt-wildcard";
  }
  // lib.optionalAttrs (cfg.certificateDomains != [ ]) { domains = cfg.certificateDomains; };
  static = {
    global = {
      checkNewVersion = false;
      sendAnonymousUsage = false;
    };
    log.level = "INFO";
    entryPoints = {
      web = {
        address = ":80/tcp";
        http.redirections.entryPoint = {
          to = "websecure";
          scheme = "https";
        };
      };
      websecure.address = ":443/tcp";
    }
    // byName tcp (entry: {
      address = ":${toString entry.port}/tcp";
    })
    // byName udp (entry: {
      address = ":${toString entry.port}/udp";
    });
    providers.file = {
      filename = "/etc/traefik/dynamic.yml";
      watch = true;
    };
    certificatesResolvers.letsencrypt-wildcard.acme = {
      storage = "/letsencrypt/acme-wildcard.json";
      dnsChallenge = {
        provider = "cloudflare";
        resolvers = [
          "1.1.1.1:53"
          "1.0.0.1:53"
        ];
      };
    };
  };
  dynamic = {
    http = {
      routers =
        builtins.listToAttrs (
          map (route: {
            name = route.hostname;
            value = {
              entryPoints = [ "websecure" ];
              rule = "Host(`${route.hostname}`)";
              service = route.hostname;
              middlewares = lib.optionals (route.cfg.private || route.service == "mcsmanager") [ "private" ];
              inherit tls;
            };
          }) routes
        )
        // builtins.listToAttrs (
          map (entry: {
            name = "${entry.hostname}-daemon";
            value = {
              entryPoints = [ "websecure" ];
              rule = "Host(`${entry.hostname}`) && PathPrefix(`/daemon/`)";
              service = "${entry.hostname}-daemon";
              middlewares = [ "private" ];
              inherit tls;
              # Preserve the native Socket.IO/upload/download prefix (no strip middleware).
            };
          }) games
        );
      services =
        builtins.listToAttrs (
          map (route: {
            name = route.hostname;
            value.loadBalancer = {
              servers = [ { url = route.cfg.backendUrl; } ];
            }
            // lib.optionalAttrs (route.service == "sunshine") { serversTransport = route.hostname; };
          }) routes
        )
        // builtins.listToAttrs (
          map (entry: {
            name = "${entry.hostname}-daemon";
            value.loadBalancer.servers = [
              {
                url = ps.require "mcsmanager" "daemonBackendUrl" entry.cfg.daemonBackendUrl;
              }
            ];
          }) games
        );
      middlewares = lib.optionalAttrs privateEnabled {
        private.ipAllowList.sourceRange = cfg.privateNetworks;
      };
      serversTransports = builtins.listToAttrs (
        map (route: {
          name = route.hostname;
          value.insecureSkipVerify = true;
        }) (lib.filter (route: route.service == "sunshine") routes)
      );
    };
    tcp = {
      routers = byName tcp (entry: {
        entryPoints = [ entry.name ];
        rule = "HostSNI(`*`)";
        service = entry.name;
        middlewares = lib.optionals entry.private [ "private" ];
      });
      services = byName tcp (entry: {
        loadBalancer.servers = [ { inherit (entry) address; } ];
      });
      middlewares = lib.optionalAttrs privateEnabled {
        private.ipAllowList.sourceRange = cfg.privateNetworks;
      };
    };
    udp = {
      routers = byName udp (entry: {
        entryPoints = [ entry.name ];
        service = entry.name;
      });
      services = byName udp (entry: {
        loadBalancer.servers = [ { inherit (entry) address; } ];
      });
    };
  };
  listenerPorts = [
    "80/tcp"
    "443/tcp"
  ]
  ++ map (entry: "${toString entry.port}/tcp") tcp
  ++ map (entry: "${toString entry.port}/udp") udp;
  publishedPorts =
    if cfg.publishedPortRanges == null then
      listenerPorts
    else
      lib.concatMap (
        range: map (port: "${toString port}/${range.protocol}") (lib.range range.start range.end)
      ) cfg.publishedPortRanges;
  publishRange =
    range:
    let
      ports =
        if range.start == range.end then
          toString range.start
        else
          "${toString range.start}-${toString range.end}";
    in
    "${ports}:${ports}" + lib.optionalString (range.protocol == "udp") "/udp";
  # JSON is a YAML subset: no extra renderer or evaluation-time build is needed.
  staticFile = pkgs.writeText "traefik.yml" (builtins.toJSON static);
  # Traefik rejects empty configuration maps (notably UDP routers without listeners).
  dynamicFile = pkgs.writeText "dynamic.yml" (
    builtins.toJSON (
      lib.filterAttrs (_: value: value != { }) (lib.filterAttrsRecursive (_: value: value != { }) dynamic)
    )
  );
in
{
  config = lib.mkIf cfg.enable {
    modules.docker.enable = true;
    modules.swarm.enable = true;
    assertions = [
      {
        assertion = native == null || (!lib.elem native.name networks && native.address != native.gateway);
        message = "traefik: nativeBackendNetwork must be distinct from backend overlays, and its container address must differ from gateway.";
      }
      {
        assertion = !privateEnabled || cfg.privateNetworks != [ ];
        message = "modules.traefik.privateNetworks is required for private HTTP/TCP routes.";
      }
      {
        assertion =
          cfg.publishedPortRanges == null
          || (
            lib.all (range: range.start <= range.end) cfg.publishedPortRanges
            && lib.sort builtins.lessThan publishedPorts == lib.sort builtins.lessThan listenerPorts
          );
        message = "modules.traefik.publishedPortRanges must cover exactly the generated listeners with ordered, non-overlapping ranges.";
      }
      {
        assertion = lib.all (
          entry:
          entry.cfg.private
          && entry.cfg.backendUrl != null
          && entry.cfg.daemonBackendUrl != null
          && !lib.elem entry.cfg.webPort (entry.cfg.tcpPorts ++ entry.cfg.udpPorts)
          && !lib.elem entry.cfg.daemonPort (entry.cfg.tcpPorts ++ entry.cfg.udpPorts)
        ) games;
        message = "MCSManager management must be private with web/daemon upstreams, and management ports must not be published as games.";
      }
      {
        assertion =
          game == null
          || lib.all (
            entry:
            entry.cfg.tcpPorts == game.cfg.tcpPorts
            && entry.cfg.udpPorts == game.cfg.udpPorts
            && entry.cfg.backendAddress == game.cfg.backendAddress
          ) games;
        message = "Traefik cannot forward the same game listener to multiple MCSManager backends.";
      }
      {
        assertion =
          mail == null
          || lib.all (
            entry:
            entry.cfg.backendAddress == mail.cfg.backendAddress
            && entry.cfg.tcpPorts == mail.cfg.tcpPorts
            && entry.cfg.private == mail.cfg.private
          ) mails;
        message = "Traefik cannot forward the same mail listener to multiple mail backends or visibility policies.";
      }
      {
        assertion =
          builtins.length (
            [
              80
              443
            ]
            ++ map (entry: entry.port) tcp
          ) == builtins.length (
            lib.unique (
              [
                80
                443
              ]
              ++ map (entry: entry.port) tcp
            )
          )
          && builtins.length udp == builtins.length (lib.unique (map (entry: entry.port) udp));
        message = "Traefik listener ports must be unique within each transport.";
      }
    ];
    environment.etc = {
      "traefik/traefik.yml".source = staticFile;
      "traefik/dynamic.yml".source = dynamicFile;
    };
    networking.firewall = {
      allowedTCPPorts = [
        80
        443
      ]
      ++ map (entry: entry.port) tcp;
      allowedUDPPorts = map (entry: entry.port) udp;
    };
    systemd.tmpfiles.rules = [
      "d ${builtins.toJSON root} 0755 root root -"
      "d ${builtins.toJSON "${root}/acme"} 0700 root root -"
    ];
    systemd.services =
      lib.optionalAttrs (native != null) {
        "docker-network-${native.name}" = {
          description = "Ensure the dedicated Traefik native-backend bridge";
          requires = [ "docker.service" ];
          after = [ "docker.service" ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script = ensureNativeNetwork;
        };
      }
      // {
        docker-traefik = {
          environment = lib.optionalAttrs (native != null) {
            DOCKER_HOST = "unix:///run/docker.sock";
            DOCKER_CONTEXT = "";
          };
          unitConfig.RequiresMountsFor = [
            root
            environmentFile
          ];
          requires = networkUnits;
          after = networkUnits;
          restartTriggers = [
            staticFile
            dynamicFile
          ];
          # Recheck after prune even when the network oneshot remains active.
          preStart = ensureNativeNetwork + ''
            : "''${CLOUDFLARE_API_TOKEN:?CLOUDFLARE_API_TOKEN is required for Traefik DNS-01}"
            umask 077
            token_file=$(mktemp /run/traefik-acme/cloudflare.env.XXXXXX)
            trap 'rm -f "$token_file"' EXIT
            printf 'CF_DNS_API_TOKEN=%s\n' "$CLOUDFLARE_API_TOKEN" > "$token_file"
            chmod 0600 "$token_file"
            mv -f "$token_file" /run/traefik-acme/cloudflare.env
          '';
          serviceConfig = {
            EnvironmentFile = environmentFile;
            RuntimeDirectory = "traefik-acme";
            RuntimeDirectoryMode = "0700";
          };
        };
      };
    virtualisation.oci-containers.containers.traefik = {
      image = lib.mkDefault "traefik:v3.7.13@sha256:24841fe2de7304c149343d877d2923b4c8800a38ba015dea9174c23b20e344a0";
      cmd = lib.mkDefault [ "--configFile=/etc/traefik/traefik.yml" ];
      autoRemoveOnStop = lib.mkDefault false;
      extraOptions = lib.mkDefault [
        "--restart=unless-stopped"
        "--user=0:0"
      ];
      ports = lib.mkDefault (
        if cfg.publishedPortRanges != null then
          map publishRange cfg.publishedPortRanges
        else
          [
            "80:80"
            "443:443"
          ]
          ++ map (entry: "${toString entry.port}:${toString entry.port}") tcp
          ++ map (entry: "${toString entry.port}:${toString entry.port}/udp") udp
      );
      networks = lib.mkDefault (
        networks ++ lib.optional (native != null) "name=${native.name},ip=${native.address},gw-priority=1"
      );
      environmentFiles = lib.mkDefault [ "/run/traefik-acme/cloudflare.env" ];
      volumes = lib.mkDefault [
        "/etc/traefik/traefik.yml:/etc/traefik/traefik.yml:ro"
        "/etc/traefik/dynamic.yml:/etc/traefik/dynamic.yml:ro"
        "${root}/acme:/letsencrypt"
      ];
    };
  };
}
