# nix-instantiate --eval --strict tests/public-services.nix --arg nixpkgs /path/to/nixpkgs --arg homeManager /path/to/home-manager
{
  nixpkgs,
  homeManager,
  system ? builtins.currentSystem,
}:
let
  t = import ./lib.nix { inherit nixpkgs homeManager system; };
  inherit (t) lib;
  evaluate =
    modules:
    (t.evalSystem {
      users = [ ];
      inherit modules;
    }).config;
  base = evaluate [ ];
  infrastructure = {
    modules = {
      swarm = {
        role = "manager";
        advertiseAddress = "10.250.0.1";
        networkSubnet = "10.251.0.0/24";
        networkGateway = "10.251.0.1";
      };
      traefik = {
        enable = true;
        dataDir = "/srv/gateway";
        environmentFile = "/run/secrets/cloudflare.env";
        privateNetworks = [ "10.252.0.0/24" ];
        certificateDomains = [
          {
            main = "example.test";
            sans = [ "*.example.test" ];
          }
        ];
      };
      dns = {
        enable = true;
        ingressAddresses = [
          "192.168.0.100"
          "10.250.0.1"
        ];
        wireguardAddress = "192.168.0.100";
      };
      cloudflare-ddns = {
        enable = true;
        records = [ "example.test" ];
        environmentFile = "/run/secrets/cloudflare.env";
      };
      cloudflare-public-cnames = {
        enable = true;
        target = "example.test";
        environmentFile = "/run/secrets/cloudflare.env";
      };
    };
    services.dnsmasq.settings.listen-address = [
      "127.0.0.1"
      "10.250.0.1"
    ];
  };
  registry.modules.public-services = {
    "vault.example.test".vaultwarden = {
      enable = true;
      host = "remote";
      deploy = false;
    };
    "search.example.test".searxng = {
      enable = true;
      host = "remote";
      deploy = false;
      private = true;
    };
    "code.example.test".code-server = {
      enable = true;
      host = "remote";
      deploy = false;
      backendUrl = "http://10.88.0.10:4444";
      private = true;
    };
    "sun.example.test".sunshine = {
      enable = true;
      host = "remote";
      deploy = false;
      backendUrl = "https://10.88.0.11:47990";
      private = true;
    };
    "ssh.example.test" = {
      ssh = {
        enable = true;
        host = "remote";
        deploy = false;
        address = "10.88.0.10";
        user = "dev";
      };
      paseo = {
        enable = true;
        host = "remote";
        deploy = false;
        private = true;
      };
    };
    "wg.example.test".wireguard-server = {
      enable = true;
      host = "remote";
      deploy = false;
    };
    "disabled.example.test".opencloud.enable = false;
  };
  gateway = evaluate [
    infrastructure
    registry
  ];
  dynamic = builtins.fromJSON gateway.environment.etc."traefik/dynamic.yml".source.text;
  static = builtins.fromJSON gateway.environment.etc."traefik/traefik.yml".source.text;
  cname = builtins.fromJSON gateway.environment.etc."cloudflare/public-cnames.json".source.text;
  aRecords = builtins.fromJSON gateway.environment.etc."cloudflare/ddns.json".source.text;
  dns = gateway.environment.etc."dnsmasq-public-services".source.text;
  bad = modules: lib.any (a: !a.assertion) (evaluate modules).assertions;
  collision = {
    modules.public-services."collision.example.test" = {
      vaultwarden = {
        enable = true;
        host = "remote";
        deploy = false;
      };
      opencloud = {
        enable = true;
        host = "remote";
        deploy = false;
      };
    };
  };
  protocolRegistry.modules.public-services = {
    "mail.example.test".mailserver = {
      enable = true;
      host = "remote";
      deploy = false;
      backendAddress = "10.250.0.2";
    };
  };
  protocols = evaluate [
    infrastructure
    protocolRegistry
  ];
  protocolsDynamic = builtins.fromJSON protocols.environment.etc."traefik/dynamic.yml".source.text;
  worker = evaluate [
    {
      modules.swarm = {
        enable = true;
        role = "worker";
        managerAddress = "10.250.0.1:2377";
        joinTokenFile = "/run/secrets/swarm-token";
      };
    }
  ];
  readiness = evaluate [
    infrastructure
    { modules.swarm.readinessAddress = "10.250.0.1"; }
  ];
  latest = evaluate [
    {
      modules.docker.enable = true;
      virtualisation.oci-containers.containers.sample = {
        image = "example:latest";
        pull = "always";
      };
    }
  ];
  directDns = evaluate [
    {
      modules.dns = {
        enable = true;
        wireguardAddress = "192.168.0.100";
      };
      modules.public-services = {
        "ssh-only.example.test".ssh = {
          enable = true;
          host = "remote";
          address = "10.88.0.10";
        };
        "wg-only.example.test".wireguard-server = {
          enable = true;
          host = "remote";
          deploy = false;
        };
      };
    }
  ];
  invalidBackendOption =
    service:
    builtins.tryEval (
      builtins.deepSeq
        (evaluate [
          {
            modules.public-services."fixed.example.test".${service}.backendUrl =
              "http://elsewhere.example.test";
          }
        ]).modules.public-services
        true
    );
  invalidType =
    builtins.tryEval
      (evaluate [ { modules.public-services."bad.example.test".vaultwarden.enable = "yes"; } ])
      .modules.public-services."bad.example.test".vaultwarden.enable;
  invalidTlsOption =
    service:
    builtins.tryEval (
      builtins.deepSeq
        (evaluate [
          {
            modules.public-services."tls.example.test".${service}.insecureSkipVerify = true;
          }
        ]).modules.public-services
        true
    );
  wrongScope =
    builtins.tryEval
      (evaluate [ { modules.vaultwarden.enable = true; } ]).modules.vaultwarden.enable;
  override = evaluate [
    infrastructure
    registry
    {
      systemd.timers.cloudflare-ddns.timerConfig.OnCalendar = "hourly";
      virtualisation.oci-containers.containers.traefik = {
        image = "traefik:test";
        autoRemoveOnStop = true;
        ports = [ "8443:443" ];
      };
    }
  ];
in
assert base.modules.public-services == { } && base.home-manager.users == { };
assert !base.modules.docker.enable && !base.modules.swarm.enable && !base.modules.traefik.enable;
assert !(base.systemd.services ? docker-traefik) && !(base.systemd.services ? cloudflare-ddns);
assert gateway.home-manager.users == { } && lib.all (a: a.assertion) gateway.assertions;
assert gateway.modules.docker.enable && gateway.modules.swarm.enable;
assert !gateway.modules.paseo.enable && !gateway.modules.openssh.enable;
assert builtins.attrNames gateway.virtualisation.oci-containers.containers == [ "traefik" ];
assert
  builtins.attrNames dynamic.http.routers == [
    "code.example.test"
    "search.example.test"
    "sun.example.test"
    "vault.example.test"
  ];
assert dynamic.http.routers."vault.example.test".rule == "Host(`vault.example.test`)";
assert dynamic.http.routers."vault.example.test".middlewares == [ ];
assert dynamic.http.routers."search.example.test".middlewares == [ "private" ];
assert dynamic.http.middlewares.private.ipAllowList.sourceRange == [ "10.252.0.0/24" ];
assert
  dynamic.http.services."code.example.test".loadBalancer.servers
  == [ { url = "http://10.88.0.10:4444"; } ];
assert builtins.attrNames dynamic.http.serversTransports == [ "sun.example.test" ];
assert dynamic.http.services."sun.example.test".loadBalancer.serversTransport == "sun.example.test";
assert !(dynamic.http.services."code.example.test".loadBalancer ? serversTransport);
assert lib.all (service: !(invalidTlsOption service).success) [
  "code-server"
  "sunshine"
];
assert lib.all (service: !(invalidBackendOption service).success) [
  "forgejo"
  "immich"
  "karakeep"
  "vaultwarden"
  "opencloud"
  "mineos"
  "jellyfin"
  "ollama"
  "searxng"
];
assert lib.all (a: a.assertion) directDns.assertions;
assert lib.hasInfix "10.88.0.10 ssh-only.example.test"
  directDns.environment.etc."dnsmasq-public-services".source.text;
assert lib.hasInfix "192.168.0.100 wg-only.example.test"
  directDns.environment.etc."dnsmasq-public-services".source.text;
assert static.entryPoints.web.http.redirections.entryPoint.scheme == "https";
assert
  cname.records == [
    "vault.example.test"
    "wg.example.test"
  ];
assert cname.target == "example.test" && aRecords.records == [ "example.test" ];
assert
  lib.hasInfix "10.88.0.10 ssh.example.test" dns && lib.hasInfix "192.168.0.100 wg.example.test" dns;
assert
  lib.hasInfix "10.250.0.1 search.example.test" dns && !lib.hasInfix "disabled.example.test" dns;
assert
  gateway.networking.firewall.allowedTCPPorts == [
    80
    443
  ];
assert gateway.networking.firewall.allowedUDPPorts == [ ];
assert
  gateway.systemd.services.docker-traefik.serviceConfig.EnvironmentFile
  == "/run/secrets/cloudflare.env";
assert !(gateway.systemd.services ? docker-swarm-token-server);
assert
  !lib.hasInfix "worker-token" readiness.systemd.services.docker-swarm-network-server.serviceConfig.ExecStart;
assert
  worker.systemd.services.docker-swarm-join.serviceConfig.LoadCredential
  == [ "join-token:/run/secrets/swarm-token" ];
assert lib.hasInfix "%d/join-token"
  worker.systemd.services.docker-swarm-join.serviceConfig.ExecStart;
assert
  protocolsDynamic.tcp.services."mail-25".loadBalancer.servers == [ { address = "10.250.0.2:25"; } ];
assert protocols.networking.firewall.allowedUDPPorts == [ ];
assert bad [ collision ];
assert bad [ { modules.public-services."bad_name".vaultwarden.enable = false; } ];
assert bad [
  {
    modules.public-services."bad.example.test".code-server = {
      enable = true;
      host = "remote";
      deploy = false;
      backendUrl = "file:///tmp/data";
    };
  }
];
assert bad [
  infrastructure
  registry
  { modules.traefik.privateNetworks = lib.mkForce [ ]; }
];
assert bad [ { modules.public-services."code.example.test".code-server.enable = true; } ];
assert bad [
  {
    modules.public-services = {
      "private.example.test".vaultwarden = {
        enable = true;
        host = "remote";
        deploy = false;
        private = true;
      };
      "public.example.test".vaultwarden = {
        enable = true;
        host = "remote";
        deploy = false;
      };
    };
  }
];
assert lib.hasInfix "is-active --quiet docker-sample"
  latest.system.activationScripts.restartLatestOciContainers.text;
assert lib.hasInfix "try-restart docker-sample"
  latest.system.activationScripts.restartLatestOciContainers.text;
assert !invalidType.success && !wrongScope.success;
assert override.systemd.timers.cloudflare-ddns.timerConfig.OnCalendar == "hourly";
assert override.virtualisation.oci-containers.containers.traefik.image == "traefik:test";
assert override.virtualisation.oci-containers.containers.traefik.autoRemoveOnStop;
assert override.virtualisation.oci-containers.containers.traefik.ports == [ "8443:443" ];
assert
  override.virtualisation.oci-containers.containers.traefik.volumes
  == gateway.virtualisation.oci-containers.containers.traefik.volumes;
assert
  override.virtualisation.oci-containers.containers.traefik.networks
  == gateway.virtualisation.oci-containers.containers.traefik.networks;
assert
  override.virtualisation.oci-containers.containers.traefik.environmentFiles
  == gateway.virtualisation.oci-containers.containers.traefik.environmentFiles;
true
