# nix-instantiate --eval --strict tests/public-apps.nix \
#   --arg nixpkgs /path/to/nixpkgs --arg homeManager /path/to/home-manager
{
  nixpkgs,
  homeManager,
  system ? builtins.currentSystem,
}:
let
  t = import ./lib.nix { inherit nixpkgs homeManager system; };
  inherit (t) lib;
  services = [
    "vaultwarden"
    "opencloud"
    "mineos"
    "jellyfin"
    "ollama"
    "searxng"
  ];
  swarm = {
    modules.swarm = {
      enable = true;
      role = "manager";
      advertiseAddress = "10.1.0.1";
      networkSubnet = "10.2.0.0/24";
      networkGateway = "10.2.0.1";
    };
  };
  inputs = {
    modules.ytdl-sub = {
      dataDir = "/srv/downloads";
      cookieFile = "/run/credentials/download-cookie";
      subscriptionFiles = {
        youtube = "/run/operations/youtube.yaml";
        twitch = "/run/operations/twitch.yaml";
      };
      uid = 1200;
      gid = 1201;
    };
    modules.open-terminal = {
      dataDir = "/srv/terminal";
      environmentFile = "/run/credentials/terminal.env";
      uid = 1300;
      gid = 1301;
    };
    # Native options, rather than hidden storage/address/GPU defaults.
    services.ollama = {
      home = "/srv/models";
      modelsDir = "/srv/models/models";
      host = "10.1.0.1";
      loadModels = [
        "embeddinggemma"
        "lfm2.5:8b-a1b-q4_K_M"
      ];
    };
  };
  localApps = {
    modules.public-services = {
      "vault.example.test".vaultwarden = {
        enable = true;
        host = "nixos";
        dataDir = "/srv/passwords";
        environmentFile = "/run/credentials/vault.env";
      };
      "cloud.example.test".opencloud = {
        enable = true;
        host = "nixos";
        dataDir = "/srv/cloud";
        environmentFile = "/run/credentials/cloud.env";
        uid = 1400;
        gid = 1401;
      };
      "mine.example.test".mineos = {
        enable = true;
        host = "nixos";
        dataDir = "/srv/minecraft";
        environmentFile = "/run/credentials/mine.env";
        uid = 1500;
        gid = 1501;
      };
      "media.example.test".jellyfin = {
        enable = true;
        host = "nixos";
        dataDir = "/srv/media-server";
        mediaDir = "/srv/downloads";
      };
      "chat.example.test".ollama = {
        enable = true;
        webui = true;
        host = "nixos";
        dataDir = "/srv/chat";
        ollamaUrl = "http://10.1.0.1:11434";
      };
      "search.example.test".searxng = {
        enable = true;
        host = "nixos";
        private = true;
        environmentFile = "/run/credentials/search.env";
      };
    };
  };
  activeModules = [
    swarm
    inputs
    localApps
  ];
  disabled = t.cfgFor [ ];
  disabledWithHost = t.cfgFor [
    {
      modules.public-services."disabled.example.test" = lib.genAttrs services (_: {
        enable = false;
      });
    }
  ];
  active = t.cfgFor activeModules;
  headless =
    (t.evalSystem {
      users = [ ];
      modules = activeModules;
    }).config;
  remoteApps = {
    modules.public-services = builtins.listToAttrs (
      map (service: {
        name = "${service}.remote.example.test";
        value.${service} = {
          enable = true;
          host = "remote";
          deploy = false;
        }
        // lib.optionalAttrs (service == "ollama") { webui = true; };
      }) services
    );
  };
  remote =
    (t.evalSystem {
      users = [ ];
      modules = [ remoteApps ];
    }).config;
  overrides = t.cfgFor (
    activeModules
    ++ [
      {
        virtualisation.oci-containers.containers = {
          vaultwarden = {
            environment.TZ = "UTC";
            autoRemoveOnStop = true;
            extraOptions = [ "--restart=on-failure" ];
          };
          opencloud.environment.OC_SHARING_PUBLIC_SHARE_MUST_HAVE_PASSWORD = "true";
          mineos-api.environment.Host__OwnerUid = "1600";
          mineos-web.environment.BODY_SIZE_LIMIT = "1G";
          jellyfin.user = "1700:1701";
          open-webui.environment = {
            RAG_EMBEDDING_MODEL = "consumer-embedding";
            CONTEXT_COMPACTION_MODEL = "consumer-compaction";
            WEB_SEARCH_RESULT_COUNT = "5";
          };
          searxng.environment.SEARXNG_LIMITER = "true";
          open-terminal.environment.OPEN_TERMINAL_MAX_SESSIONS = "8";
        };
        virtualisation.oci-containers.containers.open-terminal.environment.OPEN_TERMINAL_CORS_ALLOWED_ORIGINS =
          "https://other.example.test";
        services.ollama = {
          port = 11435;
          environmentVariables.OLLAMA_CONTEXT_LENGTH = "8192";
        };
      }
    ]
  );
  explicitSearch = t.cfgFor [
    swarm
    inputs
    {
      modules.public-services = {
        "chat.example.test".ollama = {
          enable = true;
          webui = true;
          host = "nixos";
          dataDir = "/srv/chat";
          ollamaUrl = "http://10.1.0.1:11434";
        };
        "search.example.test".searxng = {
          enable = true;
          host = "nixos";
          environmentFile = "/run/credentials/search.env";
        };
      };
    }
  ];
  remoteSearch = t.cfgFor [
    swarm
    inputs
    {
      modules.public-services = {
        "chat.example.test".ollama = {
          enable = true;
          webui = true;
          host = "nixos";
          dataDir = "/srv/chat";
          ollamaUrl = "http://10.1.0.1:11434";
        };
        "search.remote.test".searxng = {
          enable = true;
          host = "remote";
          deploy = false;
        };
      };
    }
  ];
  nativeOnly =
    (t.evalSystem {
      users = [ ];
      modules = [
        {
          modules.public-services."backend.example.test".ollama = {
            enable = true;
            host = "nixos";
            home = "/srv/ollama";
          };
        }
      ];
    }).config;
  terminalOnly =
    (t.evalSystem {
      users = [ ];
      modules = [
        swarm
        inputs
        {
          modules.open-terminal.enable = true;
          virtualisation.oci-containers.containers.open-terminal.environment.OPEN_TERMINAL_CORS_ALLOWED_ORIGINS =
            "https://terminal-client.example.test";
        }
      ];
    }).config;
  noContainers = cfg: cfg.virtualisation.oci-containers.containers == { };
  valid = cfg: lib.all (a: a.assertion) cfg.assertions;
  missing =
    name:
    builtins.tryEval (
      builtins.deepSeq
        (t.cfgFor [
          swarm
          {
            modules.public-services."missing.example.test".${name} = {
              enable = true;
              host = "nixos";
            }
            // lib.optionalAttrs (name == "ollama") { webui = true; };
          }
        ]).virtualisation.oci-containers.containers
        true
    );
  invalidPath =
    builtins.tryEval
      (t.cfgFor [ { modules.public-services."invalid.example.test".vaultwarden.dataDir = "relative"; } ])
      .modules.public-services."invalid.example.test".vaultwarden.dataDir;
  storePathInput =
    builtins.tryEval
      (t.cfgFor [
        { modules.public-services."invalid.example.test".vaultwarden.environmentFile = ../AGENTS.md; }
      ]).modules.public-services."invalid.example.test".vaultwarden.environmentFile;
  oldGlobal =
    builtins.tryEval
      (t.cfgFor [ { modules.searxng.enable = true; } ]).modules.searxng.enable;
  duplicate = t.cfgFor [
    swarm
    {
      modules.public-services = {
        "one.example.test".vaultwarden = {
          enable = true;
          host = "nixos";
          dataDir = "/srv/one";
          environmentFile = "/run/one.env";
        };
        "two.example.test".vaultwarden = {
          enable = true;
          host = "nixos";
          dataDir = "/srv/two";
          environmentFile = "/run/two.env";
        };
      };
    }
  ];
  c = active.virtualisation.oci-containers.containers;
  o = overrides.virtualisation.oci-containers.containers;
in
assert noContainers disabled && noContainers disabledWithHost && noContainers remote;
assert !disabled.modules.docker.enable && !disabled.modules.swarm.enable;
assert
  !disabled.services.ollama.enable
  && !disabled.modules.open-terminal.enable
  && !disabled.modules.ytdl-sub.enable;
assert !remote.modules.docker.enable && !remote.modules.swarm.enable;
assert
  !remote.services.ollama.enable
  && !remote.modules.open-terminal.enable
  && !remote.modules.ytdl-sub.enable;
assert
  !(remote.systemd.services ? docker-vaultwarden) && !(remote.systemd.services ? opencloud-prepare);
assert remote.home-manager.users == { };
assert valid disabled && valid disabledWithHost && valid remote && valid active && valid headless;
assert headless.home-manager.users == { };
assert active.modules.docker.enable && active.modules.swarm.enable;
assert
  active.services.ollama.enable
  && active.modules.open-terminal.enable
  && active.modules.ytdl-sub.enable;
assert
  builtins.attrNames c == [
    "jellyfin"
    "mineos-api"
    "mineos-web"
    "open-terminal"
    "open-webui"
    "opencloud"
    "searxng"
    "vaultwarden"
    "ytdl-sub"
  ];
assert c.vaultwarden.image == "vaultwarden/server:latest" && c.vaultwarden.pull == "always";
assert c.vaultwarden.volumes == [ "/srv/passwords/vw-data:/data" ];
assert c.vaultwarden.environmentFiles == [ "/run/credentials/vault.env" ];
assert !(lib.any (x: lib.hasInfix "mail.attodao.cc" x) c.vaultwarden.extraOptions);
assert c.opencloud.image == "opencloudeu/opencloud-rolling:latest" && c.opencloud.pull == "always";
assert c.opencloud.user == "1400:1401";
assert c.opencloud.environment.OC_URL == "https://cloud.example.test";
assert lib.elem "/srv/cloud/config:/etc/opencloud" c.opencloud.volumes;
assert lib.elem "/srv/cloud/data:/var/lib/opencloud" c.opencloud.volumes;
assert
  c.opencloud.cmd == [
    "-c"
    "printf 'no\\n' | opencloud init || true; exec opencloud server"
  ];
assert
  c.mineos-api.environment.ConnectionStrings__DefaultConnection == "Data Source=/app/data/mineos.db";
assert
  c.mineos-api.environment.Host__OwnerUid == "1500"
  && c.mineos-api.environment.Host__OwnerGid == "1501";
assert c.mineos-api.environment.Cors__AllowedOrigins__0 == "https://mine.example.test";
assert c.mineos-web.environment.PUBLIC_MINECRAFT_HOST == "mine.example.test";
assert c.mineos-web.environment.ORIGIN == "https://mine.example.test";
assert c.mineos-web.dependsOn == [ "mineos-api" ];
assert lib.elem "--stop-timeout=600" c.mineos-api.extraOptions;
assert
  c.jellyfin.image
  == "jellyfin/jellyfin:12.1@sha256:78d3ea1207d1322471fcac39a614f004f2ccf7e878f95ab2977d752f07e4dd7e";
assert c.jellyfin.environment.JELLYFIN_PublishedServerUrl == "https://media.example.test";
assert lib.elem "/srv/downloads:/ytdl-sub:ro" c.jellyfin.volumes;
assert lib.elem "/srv/media-server/video:/video:ro" c.jellyfin.volumes;
assert c.searxng.image == "searxng/searxng:2026.10.4-d48c4b555";
assert c.searxng.environment.SEARXNG_BASE_URL == "https://search.example.test/";
assert c.searxng.environmentFiles == [ "/run/credentials/search.env" ];
assert active.systemd.services.docker-searxng.restartTriggers != [ ];
assert c.open-webui.image == "ghcr.io/open-webui/open-webui:v0.11.4";
assert c.open-webui.environment.WEBUI_URL == "https://chat.example.test";
assert c.open-webui.environment.OLLAMA_BASE_URL == "http://10.1.0.1:11434";
assert c.open-webui.environment.RAG_OLLAMA_BASE_URL == "http://10.1.0.1:11434";
assert c.open-webui.environment.SEARXNG_QUERY_URL == "http://searxng:8080/search";
assert c.open-webui.environment.WEBUI_SECRET_KEY_FILE == "/app/backend/data/.webui_secret_key";
assert c.open-webui.environmentFiles == [ "/run/credentials/terminal.env" ];
assert
  c.open-webui.dependsOn == [
    "open-terminal"
    "searxng"
  ];
assert c.open-terminal.image == "ghcr.io/open-webui/open-terminal:0.14.0";
assert
  c.open-terminal.environment.OPEN_TERMINAL_CORS_ALLOWED_ORIGINS == "https://chat.example.test";
assert lib.elem "/srv/terminal/workspace:/home/user" c.open-terminal.volumes;
assert lib.all (name: c.${name}.networks == [ "traefik" ] && !c.${name}.autoRemoveOnStop) [
  "vaultwarden"
  "opencloud"
  "mineos-api"
  "mineos-web"
  "jellyfin"
  "searxng"
  "open-webui"
  "open-terminal"
];
assert lib.elem "docker-network-traefik.service" active.systemd.services.docker-jellyfin.after;
assert lib.elem "ollama-model-loader.service" active.systemd.services.docker-open-webui.after;
assert lib.elem "/srv/media-server"
  active.systemd.services.docker-jellyfin.unitConfig.RequiresMountsFor;
assert lib.elem "/srv/downloads"
  active.systemd.services.docker-jellyfin.unitConfig.RequiresMountsFor;
assert active.services.ollama.home == "/srv/models";
assert active.services.ollama.modelsDir == "/srv/models/models";
assert active.services.ollama.syncModels == false;
assert active.services.ollama.environmentVariables.OLLAMA_NO_CLOUD == "1";
assert active.systemd.services.ollama.serviceConfig.Restart == "on-failure";
assert
  nativeOnly.services.ollama.enable && noContainers nativeOnly && !nativeOnly.modules.docker.enable;
assert nativeOnly.services.ollama.host == "127.0.0.1";
assert nativeOnly.services.ollama.loadModels == [ ];
assert !nativeOnly.hardware.graphics.enable;
assert
  terminalOnly.modules.docker.enable
  && terminalOnly.modules.swarm.enable
  && !terminalOnly.services.ollama.enable;
assert o.vaultwarden.environment.TZ == "UTC";
assert o.vaultwarden.autoRemoveOnStop;
assert o.vaultwarden.extraOptions == [ "--restart=on-failure" ];
assert o.vaultwarden.image == c.vaultwarden.image && o.vaultwarden.pull == c.vaultwarden.pull;
assert
  o.vaultwarden.volumes == c.vaultwarden.volumes
  && o.vaultwarden.environmentFiles == c.vaultwarden.environmentFiles
  && o.vaultwarden.networks == c.vaultwarden.networks;
assert o.opencloud.environment.OC_SHARING_PUBLIC_SHARE_MUST_HAVE_PASSWORD == "true";
assert o.mineos-api.environment.Host__OwnerUid == "1600";
assert o.mineos-web.environment.BODY_SIZE_LIMIT == "1G";
assert o.jellyfin.user == "1700:1701";
assert o.open-webui.environment.RAG_EMBEDDING_MODEL == "consumer-embedding";
assert o.open-webui.environment.CONTEXT_COMPACTION_MODEL == "consumer-compaction";
assert o.open-webui.environment.WEB_SEARCH_RESULT_COUNT == "5";
assert o.searxng.environment.SEARXNG_LIMITER == "true";
assert o.open-terminal.environment.OPEN_TERMINAL_MAX_SESSIONS == "8";
assert
  o.open-terminal.environment.OPEN_TERMINAL_CORS_ALLOWED_ORIGINS == "https://other.example.test";
assert overrides.services.ollama.port == 11435;
assert overrides.services.ollama.environmentVariables.OLLAMA_CONTEXT_LENGTH == "8192";
assert
  explicitSearch.virtualisation.oci-containers.containers.open-webui.environment.SEARXNG_QUERY_URL
  == "http://searxng:8080/search";
assert
  explicitSearch.virtualisation.oci-containers.containers.open-webui.dependsOn == [
    "open-terminal"
    "searxng"
  ];
assert
  remoteSearch.virtualisation.oci-containers.containers.open-webui.environment.SEARXNG_QUERY_URL
  == "http://searxng:8080/search";
assert
  remoteSearch.virtualisation.oci-containers.containers.open-webui.dependsOn == [ "open-terminal" ];
assert lib.all (name: !(missing name).success) services;
assert !invalidPath.success && !storePathInput.success && !oldGlobal.success;
assert lib.any (
  a: !a.assertion && lib.hasInfix "only one local vaultwarden" a.message
) duplicate.assertions;
true
