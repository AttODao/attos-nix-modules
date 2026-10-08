{
  nixpkgs,
  homeManager,
  system ? builtins.currentSystem,
}:
let
  t = import ./lib.nix {
    inherit nixpkgs homeManager system;
    nixpkgsConfig.allowUnfree = true;
  };
  inherit (t) lib;
  ps = import ../modules/public-services/lib.nix { inherit lib; };
  cfg =
    modules:
    (t.evalSystem {
      users = [ ];
      inherit modules;
    }).config;
  base = cfg [ ];
  paths = name: {
    dataDir = "/srv/${name}";
    environmentFile = "/run/secrets/${name}.env";
  };
  inputs = {
    forgejo = paths "forgejo" // {
      userUid = 1000;
      userGid = 1000;
    };
    immich = paths "immich";
    karakeep = paths "karakeep" // {
      dataUid = 1000;
      dataGid = 1000;
    };
    vaultwarden = paths "vaultwarden" // {
      extraHosts.smtp = "127.0.0.1";
    };
    opencloud = paths "opencloud" // {
      uid = 1000;
      gid = 1000;
    };
    mineos = paths "mineos" // {
      uid = 1000;
      gid = 1000;
      tcpPorts = [ 25565 ];
      udpPorts = [ 19132 ];
    };
    jellyfin.dataDir = "/srv/jellyfin";
    searxng.environmentFile = "/run/secrets/searxng.env";
  };
  local = lib.mapAttrs (
    name: input:
    cfg [
      {
        modules.${name} = input // {
          enable = true;
        };
      }
    ]
  ) inputs;
  frontend = {
    forgejo = "forgejo";
    immich = "immich-server";
    karakeep = "karakeep";
    vaultwarden = "vaultwarden";
    opencloud = "opencloud";
    mineos = "mineos-web";
    jellyfin = "jellyfin";
    searxng = "searxng";
  };
  ports = {
    forgejo = "127.0.0.1:3000:3000";
    immich = "127.0.0.1:2283:2283";
    karakeep = "127.0.0.1:3001:3000";
    vaultwarden = "127.0.0.1:8000:80";
    opencloud = "127.0.0.1:9200:9200";
    mineos = "127.0.0.1:3002:3000";
    jellyfin = "127.0.0.1:8096:8096";
    searxng = "127.0.0.1:8081:8080";
  };
  valid = c: lib.all (a: a.assertion) c.assertions;
  unrouted =
    c:
    c.modules.public-services == { }
    && ps.routes c == [ ]
    && !c.modules.swarm.enable
    && !c.modules.traefik.enable
    && !c.modules.dns.enable
    && !c.modules.cloudflare-public-cnames.enable;
  isolated =
    name: c:
    let
      containers = c.virtualisation.oci-containers.containers;
    in
    valid c
    && unrouted c
    && c.modules.docker.enable
    && lib.elem ports.${name} containers.${frontend.${name}}.ports
    && lib.all (
      o: !lib.elem "traefik" o.networks && lib.all (p: lib.hasPrefix "127.0.0.1:" p) o.ports
    ) (lib.attrValues containers)
    && c.systemd.services ? docker-network-local-services
    &&
      lib.elem "docker-network-local-services.service"
        c.systemd.services."docker-${frontend.${name}}".requires;
  backend = cfg [
    {
      modules.ollama = {
        enable = true;
        home = "/srv/models";
        port = 11500;
        loadModels = [ "example" ];
      };
    }
  ];
  ui = cfg [
    {
      modules.ollama = {
        enable = true;
        webui = true;
        dataDir = "/srv/webui";
      };
    }
  ];
  integratedUi = cfg [
    {
      modules.ollama = {
        enable = true;
        webui = true;
        dataDir = "/srv/webui";
      };
      modules.searxng = inputs.searxng // {
        enable = true;
      };
      modules.open-terminal = paths "terminal" // {
        enable = true;
        uid = 1000;
        gid = 1000;
      };
    }
  ];
  native =
    (t.evalSystem {
      modules = [
        {
          modules.code-server = {
            enable = true;
            environmentFile = "/run/secrets/code.env";
          };
          modules.sunshine.enable = true;
          modules.paseo.enable = true;
          modules.ssh.server.enable = true;
        }
      ];
    }).config;
  mailInput = {
    modules.mailserver = {
      enable = true;
      dataDir = "/srv/mail";
      domains = [ "local.test" ];
      accounts."user@local.test".hashedPasswordFile = "/run/secrets/mail-hash";
      stateVersion = 5;
      dkimDomains = { };
    };
    mailserver.x509 = {
      certificateFile = "/run/mail.cert";
      privateKeyFile = "/run/mail.key";
    };
  };
  mail = cfg [ mailInput ];
  groupware = cfg [
    mailInput
    {
      modules.groupware = {
        enable = true;
        dataDir = "/srv/groupware";
        productName = "Local Mail";
      };
    }
  ];
  wg = cfg [
    {
      modules.wireguard-server = {
        enable = true;
        serverPublicKeyFile = "/run/secrets/wg-public";
        clientDns = "127.0.0.1";
      };
      networking.wireguard.interfaces.wg0 = {
        ips = [ "10.0.0.1/32" ];
        privateKeyFile = "/run/secrets/wg-private";
      };
    }
  ];
  conflict = cfg [
    {
      modules.vaultwarden = inputs.vaultwarden // {
        enable = true;
      };
      modules.public-services."vault.example.test".vaultwarden = {
        enable = true;
        host = "nixos";
      };
    }
  ];
  coexist = cfg [
    {
      modules.vaultwarden = inputs.vaultwarden // {
        enable = true;
      };
      modules.public-services."vault.example.test".vaultwarden = {
        enable = true;
        host = "another";
      };
    }
  ];
  external = cfg [
    {
      modules.vaultwarden = inputs.vaultwarden // {
        enable = true;
      };
      modules.public-services."vault.example.test".vaultwarden = {
        enable = true;
        host = "nixos";
        deploy = false;
      };
    }
  ];
  badPath =
    builtins.tryEval
      (cfg [ { modules.vaultwarden.dataDir = "relative"; } ]).modules.vaultwarden.dataDir;
  badType = builtins.tryEval (cfg [ { modules.ollama.webui = "yes"; } ]).modules.ollama.webui;
  badHostname =
    builtins.tryEval
      (cfg [ { modules.groupware.hostname = "unsafe'host"; } ]).modules.groupware.hostname;
in
assert valid base && unrouted base && base.virtualisation.oci-containers.containers == { };
assert
  !base.modules.ollama.enable && !base.modules.code-server.enable && !base.modules.ssh.server.enable;
assert lib.all (name: isolated name local.${name}) (builtins.attrNames local);
assert
  local.forgejo.virtualisation.oci-containers.containers.forgejo.environment.FORGEJO__server__ROOT_URL
  == "http://localhost:3000/";
assert
  local.forgejo.virtualisation.oci-containers.containers.forgejo.environment.FORGEJO__mailer__ENABLED
  == "false";
assert lib.elem "127.0.0.1:2222:22"
  local.forgejo.virtualisation.oci-containers.containers.forgejo.ports;
assert
  local.karakeep.virtualisation.oci-containers.containers.karakeep.environment.NEXTAUTH_URL
  == "http://localhost:3001";
assert
  local.opencloud.virtualisation.oci-containers.containers.opencloud.environment.OC_URL
  == "http://localhost:9200";
assert
  local.mineos.virtualisation.oci-containers.containers.mineos-web.environment.ORIGIN
  == "http://localhost:3002";
assert lib.elem "127.0.0.1:25565:25565/tcp"
  local.mineos.virtualisation.oci-containers.containers.mineos-api.ports;
assert lib.elem "127.0.0.1:19132:19132/udp"
  local.mineos.virtualisation.oci-containers.containers.mineos-api.ports;
assert !local.jellyfin.modules.ytdl-sub.enable;
assert
  !(lib.any (
    v: lib.hasInfix "/ytdl-sub" v
  ) local.jellyfin.virtualisation.oci-containers.containers.jellyfin.volumes);
assert
  valid backend
  && unrouted backend
  && backend.services.ollama.enable
  && !backend.modules.docker.enable;
assert backend.services.ollama.host == "127.0.0.1" && !backend.services.ollama.openFirewall;
assert backend.services.ollama.home == "/srv/models" && backend.services.ollama.port == 11500;
assert backend.services.ollama.loadModels == [ "example" ];
assert valid ui && unrouted ui && ui.services.ollama.enable;
assert !ui.modules.open-terminal.enable && !ui.modules.searxng.enable;
assert builtins.attrNames ui.virtualisation.oci-containers.containers == [ "open-webui" ];
assert ui.virtualisation.oci-containers.containers.open-webui.networks == [ ];
assert lib.elem "--network=host"
  ui.virtualisation.oci-containers.containers.open-webui.extraOptions;
assert ui.virtualisation.oci-containers.containers.open-webui.environment.HOST == "127.0.0.1";
assert
  ui.virtualisation.oci-containers.containers.open-webui.environment.OLLAMA_BASE_URL
  == "http://127.0.0.1:11434";
assert
  ui.virtualisation.oci-containers.containers.open-webui.environment.ENABLE_WEB_SEARCH == "false";
assert
  ui.virtualisation.oci-containers.containers.open-webui.environment.ENABLE_CODE_INTERPRETER
  == "true";
assert
  ui.virtualisation.oci-containers.containers.open-webui.environment.RAG_OLLAMA_BASE_URL
  == "http://127.0.0.1:11434";
assert
  ui.virtualisation.oci-containers.containers.open-webui.environment.ENABLE_CONTEXT_COMPACTION
  == "true";
assert ui.virtualisation.oci-containers.containers.open-webui.environmentFiles == [ ];
assert valid integratedUi && unrouted integratedUi;
assert
  integratedUi.virtualisation.oci-containers.containers.open-webui.environment.SEARXNG_QUERY_URL
  == "http://127.0.0.1:8081/search";
assert
  integratedUi.virtualisation.oci-containers.containers.open-terminal.environment.OPEN_TERMINAL_CORS_ALLOWED_ORIGINS
  == "http://localhost:8080";
assert
  integratedUi.virtualisation.oci-containers.containers.open-terminal.ports
  == [ "127.0.0.1:8001:8000" ];
assert valid native && unrouted native;
assert
  native.services.code-server.host == "127.0.0.1"
  && native.services.sunshine.settings.bind_address == "127.0.0.1";
assert
  native.services.openssh.listenAddresses == [
    {
      addr = "127.0.0.1";
      port = null;
    }
  ];
assert !native.services.openssh.openFirewall && native.modules.paseo.hostname == "localhost";
assert valid mail && unrouted mail && mail.mailserver.x509.useACMEHost == null;
assert mail.services.postfix.settings.main.inet_interfaces == [ "loopback-only" ];
assert
  mail.services.dovecot2.settings.listen == [
    "127.0.0.1"
    "::1"
  ];
assert valid groupware && unrouted groupware && groupware.services.radicale.enable;
assert (builtins.head groupware.services.nginx.virtualHosts.localhost.listen).addr == "127.0.0.1";
assert valid wg && unrouted wg && wg.networking.wireguard.interfaces.wg0.listenPort == 51820;
assert
  wg.modules.wireguard-server.hostname == "localhost" && !wg.modules.wireguard-server.ipv4Forwarding;
assert !valid conflict && valid coexist && valid external;
assert !badPath.success && !badType.success && !badHostname.success;
true
