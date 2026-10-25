{
  config,
  lib,
  pkgs,
  ps,
  ...
}:
let
  cfg = config.modules.traefik;
  environmentFile = ps.require "modules.traefik" "environmentFile" cfg.environmentFile;
  routes = ps.routes config;
  games = ps.entries config "mcsmanager";
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
    ))
    # Forgejo publishes SSH on its backendUrl address; listen only on the selected gateway addresses.
    ++ lib.concatMap (
      entry:
      let
        listener = suffix: listen: {
          name = "forgejo-ssh${suffix}";
          port = 22;
          inherit listen;
          address = "${
            (ps.backendEndpoint {
              service = "forgejo";
              inherit (entry) cfg;
            }).address
          }:${toString ps.forgejoSshBackendPort}";
          inherit (entry.cfg) private;
        };
      in
      if entry.cfg.sshAddresses == [ ] then
        [ (listener "" null) ]
      else
        lib.imap0 (index: address: listener "-${toString index}" address) entry.cfg.sshAddresses
    ) (ps.entries config "forgejo");
  listenKey =
    entry:
    if entry.listen or null == null then entry.port else "${entry.listen}:${toString entry.port}";
  bound = lib.filter (entry: entry.listen or null != null) tcp;
  unbound = lib.filter (entry: entry.listen or null == null) tcp;
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
  # Every HTTPS router carries the shared security headers; private routes add the allowlist.
  httpMiddlewares = extra: [ "security-headers" ] ++ extra;
  extraPrivate = route: route.cfg.private && route.cfg.privateExtraNetworks != [ ];
  privateMiddleware =
    route:
    if extraPrivate route then
      "private-${route.hostname}-${route.service or "mcsmanager"}"
    else
      "private";
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
      address = "${if entry.listen or null == null then "" else entry.listen}:${toString entry.port}/tcp";
    })
    // byName udp (entry: {
      address = ":${toString entry.port}/udp";
    });
    providers.file = {
      filename = "/etc/traefik/dynamic.yml";
      watch = true;
    };
    certificatesResolvers.letsencrypt-wildcard.acme = {
      storage = "${config.services.traefik.dataDir}/acme-wildcard.json";
      dnsChallenge = {
        provider = "cloudflare";
        resolvers = [
          "1.1.1.1:53"
          "1.0.0.1:53"
        ];
      };
    };
  }
  // lib.optionalAttrs cfg.accessLog.enable {
    accessLog = {
      filePath = "/var/log/traefik/access.log";
      format = "json";
      bufferingSize = 0;
      fields = {
        defaultMode = "drop";
        names = lib.genAttrs [
          "ClientHost"
          "RequestHost"
          "RequestMethod"
          "RequestPath"
          "DownstreamStatus"
          "RouterName"
        ] (_: "keep");
        headers.defaultMode = "drop";
        # OAuth codes, reset links and other query secrets must not enter the log.
        queryParameters.defaultMode = "drop";
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
              middlewares = httpMiddlewares (
                lib.optionals (route.cfg.private || route.service == "mcsmanager") [ (privateMiddleware route) ]
              );
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
              middlewares = httpMiddlewares [ (privateMiddleware entry) ];
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
            };
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
      middlewares = {
        # HSTS and nosniff for every HTTPS route; frame/CSP policies stay with the applications.
        security-headers.headers = {
          stsSeconds = 31536000;
          stsIncludeSubdomains = false;
          contentTypeNosniff = true;
        };
      }
      // lib.optionalAttrs privateEnabled {
        private.ipAllowList.sourceRange = cfg.privateNetworks;
      }
      // builtins.listToAttrs (
        map (route: {
          name = privateMiddleware route;
          value.ipAllowList.sourceRange = cfg.privateNetworks ++ route.cfg.privateExtraNetworks;
        }) (lib.filter extraPrivate routes)
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
    # Applies to every TLS router (HTTP and TCP) that does not name its own options.
    tls.options.default.minVersion = "VersionTLS12";
  };
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
    assertions = [
      {
        assertion = !privateEnabled || cfg.privateNetworks != [ ];
        message = "modules.traefik.privateNetworks is required for private HTTP/TCP routes.";
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
            ++ map listenKey tcp
          ) == builtins.length (
            lib.unique (
              [
                80
                443
              ]
              ++ map listenKey tcp
            )
          )
          && builtins.length udp == builtins.length (lib.unique (map (entry: entry.port) udp));
        message = "Traefik listener ports must be unique within each transport.";
      }
    ];
    environment.etc."traefik/dynamic.yml".source = dynamicFile;
    networking.firewall = {
      allowedTCPPorts = [
        80
        443
      ]
      ++ map (entry: entry.port) unbound;
      allowedUDPPorts = map (entry: entry.port) udp;
      # Address-bound listeners open only their own address, not other host listeners on the port.
      extraInputRules = lib.mkIf config.networking.nftables.enable (
        lib.concatMapStrings (entry: ''
          ip daddr ${entry.listen} tcp dport ${toString entry.port} accept
        '') bound
      );
      extraCommands = lib.mkIf (!config.networking.nftables.enable) (
        lib.concatMapStrings (entry: ''
          iptables -A nixos-fw -d ${entry.listen} -p tcp --dport ${toString entry.port} -j nixos-fw-accept
        '') bound
      );
    };
    services.traefik = {
      enable = true;
      staticConfigFile = staticFile;
    };
    systemd.services.traefik = {
      unitConfig.RequiresMountsFor = [ environmentFile ];
      # Bound listeners need their addresses configured before Traefik binds them.
      wants = ps.afterNetworkOnline.wants ++ cfg.listenServices;
      after = ps.afterNetworkOnline.after ++ cfg.listenServices;
      serviceConfig = {
        # network-online.target may be reached via another link (wait-online --any), so wait per address.
        ExecStartPre = lib.mkIf (bound != [ ]) (
          pkgs.writeShellScript "traefik-wait-addresses" ''
            for address in ${lib.escapeShellArgs (lib.unique (map (entry: entry.listen) bound))}; do
              for _ in $(seq 60); do
                [ -n "$(${pkgs.iproute2}/bin/ip -o addr show to "$address")" ] && continue 2
                sleep 1
              done
              echo "address $address was not configured within 60s" >&2
              exit 1
            done
          ''
        );
        EnvironmentFile = environmentFile;
        # The Cloudflare DNS-01 provider reads CF_DNS_API_TOKEN.
        ExecStart = lib.mkForce (
          pkgs.writeShellScript "traefik-start" ''
            : "''${CLOUDFLARE_API_TOKEN:?CLOUDFLARE_API_TOKEN is required for Traefik DNS-01}"
            export CF_DNS_API_TOKEN="$CLOUDFLARE_API_TOKEN"
            exec ${lib.getExe config.services.traefik.package} --configfile=${staticFile}
          ''
        );
      };
    };
  };
}
