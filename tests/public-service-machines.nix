# The same catalog is consumed by physical hosts and guest configurations.
{
  nixpkgs,
  homeManager,
  system ? builtins.currentSystem,
}:
let
  t = import ./lib.nix { inherit nixpkgs homeManager system; };
  inherit (t) lib;
  evaluate =
    hostName: modules:
    (t.evalSystem {
      users = [ ];
      modules = [ { networking.hostName = hostName; } ] ++ modules;
    }).config;
  registry.modules.public-services = {
    "vault.example.test".vaultwarden = {
      enable = true;
      host = "attobox";
    };
    "search.example.test".searxng = {
      enable = true;
      host = "attofort";
    };
    "code.example.test".code-server = {
      enable = true;
      host = "development";
      backendUrl = "http://10.88.0.10:4444";
    };
    "sun.example.test".sunshine = {
      enable = true;
      host = "desktop";
      backendUrl = "https://10.88.0.11:47990";
    };
    "ssh-a.example.test".ssh = {
      enable = true;
      host = "attobox";
      address = "10.250.0.2";
    };
    "ssh-b.example.test".ssh = {
      enable = true;
      host = "attofort";
      address = "10.250.0.1";
    };
  };
  swarm.modules.swarm = {
    role = "manager";
    advertiseAddress = "10.250.0.1";
  };
  gateway = evaluate "gateway" [
    registry
    swarm
    {
      modules.traefik = {
        enable = true;
        dataDir = "/srv/traefik";
        environmentFile = "/run/secrets/cloudflare.env";
      };
      modules.dns = {
        enable = true;
        ingressAddresses = [ "10.250.0.1" ];
      };
      modules.cloudflare-public-cnames = {
        enable = true;
        target = "example.test";
        environmentFile = "/run/secrets/cloudflare.env";
      };
    }
  ];
  attobox = evaluate "attobox" [
    registry
    swarm
    {
      modules.public-services."vault.example.test".vaultwarden = {
        dataDir = "/srv/vault";
        environmentFile = "/run/secrets/vault.env";
      };
    }
  ];
  attofort = evaluate "attofort" [
    registry
    swarm
    {
      modules.public-services."search.example.test".searxng.environmentFile = "/run/secrets/search.env";
    }
  ];
  groupware = evaluate "gateway" [
    {
      modules.public-services."mail.example.test".groupware = {
        enable = true;
        host = "mail";
        backendUrl = "http://10.250.0.2:8080";
      };
    }
  ];
  external = evaluate "attobox" [
    registry
    {
      modules.public-services."ssh-a.example.test".ssh.deploy = lib.mkForce false;
      modules.public-services."vault.example.test".vaultwarden = {
        deploy = false;
        backendUrl = "http://vault.external:8080";
      };
    }
  ];
  disabled = evaluate "attobox" [
    {
      modules.public-services = lib.mapAttrs (
        _: services: lib.mapAttrs (_: cfg: cfg // { enable = false; }) services
      ) registry.modules.public-services;
    }
  ];
  duplicate = evaluate "attobox" [
    registry
    {
      modules.public-services."vault-b.example.test".vaultwarden = {
        enable = true;
        host = "attobox";
      };
    }
  ];
  missing = evaluate "gateway" [
    { modules.public-services."missing.example.test".vaultwarden.enable = true; }
  ];
  invalid =
    builtins.tryEval
      (evaluate "gateway" [
        {
          modules.public-services."bad.example.test".vaultwarden.host = "";
        }
      ]).modules.public-services."bad.example.test".vaultwarden.host;
  obsolete =
    builtins.tryEval
      (evaluate "gateway" [
        {
          modules.public-services."bad.example.test".vaultwarden.machine = "attobox";
        }
      ]).modules.public-services."bad.example.test".vaultwarden.machine;
  peers.modules.public-services = {
    "llm.example.test".ollama = {
      enable = true;
      host = "web";
      webui = true;
      dataDir = "/srv/webui";
      ollamaUrl = "http://10.250.0.2:11434";
    };
    "search.example.test".searxng = {
      enable = true;
      host = "search";
    };
    "vault.example.test".vaultwarden = {
      enable = true;
      host = "vault";
    };
  };
  peerWeb = evaluate "web" [
    peers
    {
      modules.swarm = {
        role = "worker";
        managerAddress = "10.250.0.1:2377";
        joinTokenFile = "/run/secrets/worker-token";
      };
      modules.open-terminal = {
        dataDir = "/srv/terminal";
        environmentFile = "/run/secrets/terminal.env";
        uid = 1100;
        gid = 1100;
      };
    }
  ];
  peerGateway = evaluate "gateway" [
    peers
    swarm
    {
      modules.traefik = {
        enable = true;
        dataDir = "/srv/traefik";
        environmentFile = "/run/secrets/cloudflare.env";
      };
    }
  ];
  ps = import ../modules/public-services/lib.nix { inherit lib; };
  dynamic = builtins.fromJSON gateway.environment.etc."traefik/dynamic.yml".source.text;
  cnames = builtins.fromJSON gateway.environment.etc."cloudflare/public-cnames.json".source.text;
  dns = gateway.environment.etc."dnsmasq-public-services".source.text;
in
assert lib.all (a: a.assertion) gateway.assertions;
assert gateway.virtualisation.oci-containers.containers ? traefik;
assert (ps.select attobox "vaultwarden").service == "vaultwarden";
assert
  attobox.virtualisation.oci-containers.containers.vaultwarden.networks == [ "backend-vaultwarden" ];
assert attofort.virtualisation.oci-containers.containers.searxng.networks == [ "backend-searxng" ];
assert
  lib.sort builtins.lessThan gateway.virtualisation.oci-containers.containers.traefik.networks == [
    "backend-searxng"
    "backend-vaultwarden"
  ];
assert lib.all (a: a.assertion) peerWeb.assertions;
assert
  lib.sort builtins.lessThan peerWeb.virtualisation.oci-containers.containers.open-webui.networks == [
    "backend-ollama"
    "backend-open-terminal"
    "backend-searxng"
  ];
assert
  peerWeb.virtualisation.oci-containers.containers.open-terminal.networks
  == [ "backend-open-terminal" ];
assert !(peerWeb.systemd.services ? docker-network-backend-vaultwarden);
assert lib.all
  (
    name:
    lib.elem "docker-network-${name}.service" peerWeb.systemd.services.docker-open-webui.requires
    && lib.hasSuffix " wait ${
       lib.escapeShellArgs [
         "http://10.250.0.1:2378/networks-ready/${name}"
         name
       ]
     }" peerWeb.systemd.services."docker-network-${name}".serviceConfig.ExecStart
  )
  [
    "backend-ollama"
    "backend-open-terminal"
    "backend-searxng"
  ];
assert
  lib.sort builtins.lessThan peerGateway.virtualisation.oci-containers.containers.traefik.networks
  == [
    "backend-ollama"
    "backend-searxng"
    "backend-vaultwarden"
  ];
assert peerGateway.systemd.services ? docker-network-backend-open-terminal;
assert lib.elem "docker-swarm-networks.service"
  peerGateway.systemd.services.docker-network-backend-vaultwarden.requires;
assert lib.hasInfix "backend-vaultwarden"
  peerGateway.systemd.services.docker-swarm-networks.serviceConfig.ExecStart;
assert !(gateway.virtualisation.oci-containers.containers ? vaultwarden);
assert !(gateway.virtualisation.oci-containers.containers ? searxng);
assert !gateway.services.code-server.enable && !gateway.services.sunshine.enable;
assert !gateway.modules.hyprland.enable && !gateway.modules.steam.enable;
assert !gateway.modules.openssh.enable;
assert builtins.length (builtins.attrNames dynamic.http.routers) == 4;
assert
  dynamic.http.services."vault.example.test".loadBalancer.servers
  == [ { url = "http://vaultwarden:80"; } ];
assert
  dynamic.http.services."search.example.test".loadBalancer.servers
  == [ { url = "http://searxng:8080"; } ];
assert
  lib.elem "vault.example.test" cnames.records && lib.elem "search.example.test" cnames.records;
assert lib.hasInfix "10.250.0.2 ssh-a.example.test" dns;
assert lib.hasInfix "10.250.0.1 ssh-b.example.test" dns;
assert
  attobox.virtualisation.oci-containers.containers.vaultwarden.volumes
  == [ "/srv/vault/vw-data:/data" ];
assert
  attofort.virtualisation.oci-containers.containers.searxng.environmentFiles
  == [ "/run/secrets/search.env" ];
assert !(attobox.virtualisation.oci-containers.containers ? searxng);
assert !(attofort.virtualisation.oci-containers.containers ? vaultwarden);
assert attobox.modules.openssh.enable && attofort.modules.openssh.enable;
assert lib.all (a: a.assertion) attobox.assertions && lib.all (a: a.assertion) attofort.assertions;
assert groupware.modules.public-services."mail.example.test".mailserver.enable;
assert groupware.modules.public-services."mail.example.test".mailserver.host == "mail";
assert !groupware.mailserver.enable && !(groupware.systemd.services ? radicale);
assert
  !external.modules.openssh.enable
  && !(external.virtualisation.oci-containers.containers ? vaultwarden);
assert
  !disabled.modules.openssh.enable
  && !disabled.services.code-server.enable
  && !disabled.services.sunshine.enable;
assert lib.all (a: a.assertion) disabled.assertions;
assert lib.any (
  a: !a.assertion && lib.hasInfix "only one local vaultwarden" a.message
) duplicate.assertions;
assert lib.any (
  a: !a.assertion && lib.hasInfix ".host must name the owner" a.message
) missing.assertions;
assert !invalid.success && !obsolete.success;
true
