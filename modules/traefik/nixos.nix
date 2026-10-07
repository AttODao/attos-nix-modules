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
  games = ps.entries config "mineos";
  mails = ps.entries config "mailserver";
  game = if games == [ ] then null else builtins.head games;
  mail = if mails == [ ] then null else builtins.head mails;
  tcp =
    (lib.optionals (game != null) (
      map (port: {
        name = "minecraft-${toString port}";
        inherit port;
        address = "api:${toString port}";
        private = game.cfg.private;
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
      address = "api:${toString port}";
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
  privateEnabled = lib.any (route: route.cfg.private) routes || lib.any (entry: entry.private) tcp;
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
      routers = builtins.listToAttrs (
        map (route: {
          name = route.hostname;
          value = {
            entryPoints = [ "websecure" ];
            rule = "Host(`${route.hostname}`)";
            service = route.hostname;
            middlewares = lib.optionals route.cfg.private [ "private" ];
            inherit tls;
          };
        }) routes
      );
      services = builtins.listToAttrs (
        map (route: {
          name = route.hostname;
          value.loadBalancer = {
            servers = [ { url = route.cfg.backendUrl; } ];
          }
          // lib.optionalAttrs (route.service == "sunshine") { serversTransport = route.hostname; };
        }) routes
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
  # JSON is a YAML subset: no extra renderer or evaluation-time build is needed.
  staticFile = pkgs.writeText "traefik.yml" (builtins.toJSON static);
  dynamicFile = pkgs.writeText "dynamic.yml" (builtins.toJSON dynamic);
in
{
  config = lib.mkIf cfg.enable {
    modules.docker.enable = true;
    modules.swarm.enable = true;
    assertions = [
      {
        assertion = !privateEnabled || cfg.privateNetworks != [ ];
        message = "modules.traefik.privateNetworks is required for private HTTP/TCP routes.";
      }
      {
        assertion =
          game == null
          || lib.all (
            entry:
            entry.cfg.tcpPorts == game.cfg.tcpPorts
            && entry.cfg.udpPorts == game.cfg.udpPorts
            && entry.cfg.private == game.cfg.private
          ) games;
        message = "Traefik cannot forward the same Minecraft listener to multiple game backends or visibility policies.";
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
        assertion = game == null || !game.cfg.private || game.cfg.udpPorts == [ ];
        message = "Private MineOS UDP ingress is not protected by Traefik middleware; set udpPorts = [ ] and configure VPN-only ingress in the consumer.";
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
    systemd.services.docker-traefik = {
      unitConfig.RequiresMountsFor = [
        root
        environmentFile
      ];
      wants = [ "docker-network-traefik.service" ];
      after = [ "docker-network-traefik.service" ];
      restartTriggers = [
        staticFile
        dynamicFile
      ];
      preStart = ''
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
    virtualisation.oci-containers.containers.traefik = {
      image = lib.mkDefault "traefik:v3.7.13";
      cmd = lib.mkDefault [ "--configFile=/etc/traefik/traefik.yml" ];
      autoRemoveOnStop = lib.mkDefault false;
      extraOptions = lib.mkDefault [
        "--restart=unless-stopped"
        "--user=0:0"
      ];
      ports = lib.mkDefault (
        [
          "80:80"
          "443:443"
        ]
        ++ map (entry: "${toString entry.port}:${toString entry.port}") tcp
        ++ map (entry: "${toString entry.port}:${toString entry.port}/udp") udp
      );
      networks = lib.mkDefault [ "traefik" ];
      environmentFiles = lib.mkDefault [ "/run/traefik-acme/cloudflare.env" ];
      volumes = lib.mkDefault [
        "/etc/traefik/traefik.yml:/etc/traefik/traefik.yml:ro"
        "/etc/traefik/dynamic.yml:/etc/traefik/dynamic.yml:ro"
        "${root}/acme:/letsencrypt"
      ];
    };
  };
}
