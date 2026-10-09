{
  config,
  lib,
  options,
  ...
}:
let
  ps = import ../public-services/lib.nix { inherit lib; };
  s = ps.select config "ollama";
  root = ps.require "open-webui" "dataDir" s.cfg.dataDir;
  terminalEnabled = !s.standalone || config.modules.open-terminal.enable;
  environmentFile =
    ps.require "open-webui" "modules.open-terminal.environmentFile"
      config.modules.open-terminal.environmentFile;
  ollamaUrl =
    if s.standalone && s.cfg.ollamaUrl == null then
      "http://127.0.0.1:${toString config.services.ollama.port}"
    else
      ps.require "open-webui" "ollamaUrl" s.cfg.ollamaUrl;
  searchRoutes = lib.filter (route: route.service == "searxng") (ps.routes config);
  localSearch = ps.select config "searxng";
  searchEnabled = !s.standalone || config.modules.searxng.enable;
  transports = [
    s
  ]
  ++ lib.optional terminalEnabled {
    standalone = s.standalone;
    service = "open-terminal";
  }
  ++
    lib.optional (searchEnabled && (s.standalone || lib.any (route: route.cfg.deploy) searchRoutes))
      {
        standalone = s.standalone;
        service = "searxng";
      };
  searxngUrl =
    if s.standalone then
      "http://127.0.0.1:8081/search"
    else
      ps.require "open-webui" "an enabled SearXNG registry entry" (
        if searchRoutes == [ ] then null else "${(builtins.head searchRoutes).cfg.backendUrl}/search"
      );
in
{
  imports = [
    ./nixos.nix
    ../docker
    ../swarm
    ../open-terminal
    ../searxng
  ];

  options.modules = ps.moduleOptions "ollama" (
    ps.common "Ollama with optional Open WebUI"
    //
      lib.mapAttrs
        (
          _: option:
          lib.mkOption {
            inherit (option) type default description;
          }
        )
        (
          lib.getAttrs [
            "package"
            "home"
            "modelsDir"
            "port"
            "loadModels"
            "environmentVariables"
          ] options.services.ollama
        )
    // {
      listenAddress = lib.mkOption {
        inherit (options.services.ollama.host) type default description;
      };
      webui = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable the optional Open WebUI frontend with Docker; public deployment also requires Swarm/Terminal. False runs only Ollama and creates no HTTP proxy route.";
      };
      dataDir = ps.pathOption "Service root containing the existing data directory and persistent authentication state.";
      ollamaUrl = lib.mkOption {
        type = lib.types.nullOr lib.types.nonEmptyStr;
        default = null;
        description = "Consumer-selected Ollama HTTP endpoint reachable from the container; standalone defaults to http://127.0.0.1 at the native services.ollama.port, while public WebUI requires an explicit endpoint. Listener routing/firewall remain consumer-owned.";
      };
    }
  );

  config = lib.mkMerge [
    { assertions = s.assertions; }
    (lib.mkIf (s.enabled && s.cfg.webui) {
      modules.docker.enable = true;
      modules.swarm.enable = lib.mkIf (!s.standalone) true;
      modules.open-terminal.enable = lib.mkIf (!s.standalone) true;

      systemd.tmpfiles.rules = [
        "d ${builtins.toJSON root} 0700 root root -"
        "d ${builtins.toJSON "${root}/data"} 0700 root root -"
      ];
      systemd.services.docker-open-webui = {
        unitConfig.RequiresMountsFor = [ root ] ++ lib.optional terminalEnabled environmentFile;
        wants = lib.optionals (!s.standalone) (map ps.networkUnit transports) ++ [
          "ollama.service"
          "ollama-model-loader.service"
        ];
        after = lib.optionals (!s.standalone) (map ps.networkUnit transports) ++ [
          "ollama.service"
          "ollama-model-loader.service"
        ];
      };
      virtualisation.oci-containers.containers.open-webui = {
        image = lib.mkDefault "ghcr.io/open-webui/open-webui:v0.11.4@sha256:9591b13f13843c7721c2b8eaf7382846c81b3ffe126526d1888d1fed50c6a33f";
        environmentFiles = lib.mkDefault (lib.optional terminalEnabled environmentFile);
        environment = lib.mapAttrs (_: lib.mkDefault) (
          {
            WEBUI_URL = ps.url s 8080;
            OLLAMA_BASE_URL = ollamaUrl;
            WEBUI_SECRET_KEY_FILE = "/app/backend/data/.webui_secret_key";
            DEFAULT_MODEL_METADATA = builtins.toJSON (
              {
                capabilities = {
                  builtin_tools = true;
                  code_interpreter = true;
                  terminal = terminalEnabled;
                  web_search = searchEnabled;
                };
                defaultFeatureIds = lib.optional searchEnabled "web_search" ++ [ "code_interpreter" ];
              }
              // lib.optionalAttrs terminalEnabled { terminalId = "open-terminal"; }
            );
            ENABLE_WEB_SEARCH = lib.boolToString searchEnabled;
            ENABLE_RAG_HYBRID_SEARCH = "true";
            ENABLE_CODE_EXECUTION = "true";
            ENABLE_CODE_INTERPRETER = "true";
            ENABLE_CONTEXT_COMPACTION = "true";
          }
          // lib.optionalAttrs searchEnabled {
            WEB_SEARCH_ENGINE = "searxng";
            SEARXNG_QUERY_URL = searxngUrl;
            SEARXNG_LANGUAGE = "all";
            WEB_SEARCH_RESULT_COUNT = "3";
            WEB_SEARCH_CONCURRENT_REQUESTS = "2";
            WEB_LOADER_CONCURRENT_REQUESTS = "3";
            WEB_FETCH_MAX_CONTENT_LENGTH = "20000";
          }
          // {
            DEFAULT_MODEL_PARAMS = builtins.toJSON { function_calling = "native"; };
            RAG_EMBEDDING_ENGINE = "ollama";
            RAG_EMBEDDING_MODEL = "embeddinggemma";
            RAG_OLLAMA_BASE_URL = ollamaUrl;
            CODE_EXECUTION_ENGINE = "pyodide";
            CODE_INTERPRETER_ENGINE = "pyodide";
            ENABLE_PYODIDE_FILE_PERSISTENCE = "false";
            CONTEXT_COMPACTION_MODEL = "lfm2.5:8b-a1b-q4_K_M";
            CONTEXT_COMPACTION_TOKEN_THRESHOLD = "24000";
            CONTEXT_COMPACTION_TOKEN_CAP = "32000";
            CONTEXT_COMPACTION_RETENTION_PERCENTAGE = "40";
          }
          // lib.optionalAttrs s.standalone {
            HOST = "127.0.0.1";
            PORT = "8080";
          }
        );
        autoRemoveOnStop = lib.mkDefault false;
        # v0.11.4 backend/start.sh passes HOST/PORT to uvicorn; host networking
        # reaches loopback Ollama without widening either service's listener.
        extraOptions = lib.mkDefault (
          [ "--restart=unless-stopped" ]
          ++ [
            (if s.standalone then "--network=host" else "--network-alias=open-webui")
          ]
        );
        volumes = lib.mkDefault [
          "${root}/data:/app/backend/data"
          "/etc/localtime:/etc/localtime:ro"
        ];
        dependsOn =
          lib.optional terminalEnabled "open-terminal"
          ++ lib.optional (localSearch.enabled && (!s.standalone || searchEnabled)) "searxng";
        networks = lib.mkDefault (lib.optionals (!s.standalone) (map ps.network transports));
      };
    })
  ];
}
