{ config, lib, ... }:
let
  ps = import ../public-services/lib.nix { inherit lib; };
  s = ps.select config "open-webui";
  root = ps.require "open-webui" "dataDir" s.cfg.dataDir;
  environmentFile =
    ps.require "open-webui" "modules.open-terminal.environmentFile"
      config.modules.open-terminal.environmentFile;
  ollamaUrl = ps.require "open-webui" "ollamaUrl" s.cfg.ollamaUrl;
  searchRoutes = lib.filter (route: route.service == "searxng") (ps.routes config);
  searxngUrl = ps.require "open-webui" "an enabled SearXNG registry entry" (
    if searchRoutes == [ ] then null else "${(builtins.head searchRoutes).cfg.backendUrl}/search"
  );
  localSearch = ps.select config "searxng";
in
{
  imports = [
    ../docker
    ../swarm
    ../ollama
    ../open-terminal
    ../searxng
  ];

  options.modules.public-services = ps.option "open-webui" (
    ps.common "Open WebUI"
    // {
      dataDir = ps.pathOption "Service root containing the existing data directory and persistent authentication state.";
      ollamaUrl = lib.mkOption {
        type = lib.types.nullOr lib.types.nonEmptyStr;
        default = null;
        description = "Consumer-selected Ollama HTTP endpoint reachable from the container; the consumer configures the native listener/network.";
      };
    }
  );

  config = lib.mkMerge [
    { assertions = s.assertions; }
    (lib.mkIf s.enabled {
      modules.docker.enable = true;
      modules.swarm.enable = true;
      modules.ollama.enable = true;
      modules.open-terminal.enable = true;

      systemd.tmpfiles.rules = [
        "d ${builtins.toJSON root} 0700 root root -"
        "d ${builtins.toJSON "${root}/data"} 0700 root root -"
      ];
      systemd.services.docker-open-webui = {
        unitConfig.RequiresMountsFor = [
          root
          environmentFile
        ];
        wants = [
          "docker-network-traefik.service"
          "ollama.service"
          "ollama-model-loader.service"
        ];
        after = [
          "docker-network-traefik.service"
          "ollama.service"
          "ollama-model-loader.service"
        ];
      };
      virtualisation.oci-containers.containers.open-webui = {
        image = lib.mkDefault "ghcr.io/open-webui/open-webui:v0.11.4";
        environmentFiles = lib.mkDefault [ environmentFile ];
        environment = lib.mapAttrs (_: lib.mkDefault) {
          WEBUI_URL = "https://${s.hostname}";
          OLLAMA_BASE_URL = ollamaUrl;
          WEBUI_SECRET_KEY_FILE = "/app/backend/data/.webui_secret_key";
          DEFAULT_MODEL_METADATA = builtins.toJSON {
            capabilities = {
              builtin_tools = true;
              code_interpreter = true;
              terminal = true;
              web_search = true;
            };
            defaultFeatureIds = [
              "web_search"
              "code_interpreter"
            ];
            terminalId = "open-terminal";
          };
          DEFAULT_MODEL_PARAMS = builtins.toJSON { function_calling = "native"; };
          ENABLE_WEB_SEARCH = "true";
          WEB_SEARCH_ENGINE = "searxng";
          SEARXNG_QUERY_URL = searxngUrl;
          SEARXNG_LANGUAGE = "all";
          WEB_SEARCH_RESULT_COUNT = "3";
          WEB_SEARCH_CONCURRENT_REQUESTS = "2";
          WEB_LOADER_CONCURRENT_REQUESTS = "3";
          WEB_FETCH_MAX_CONTENT_LENGTH = "20000";
          RAG_EMBEDDING_ENGINE = "ollama";
          RAG_EMBEDDING_MODEL = "embeddinggemma";
          RAG_OLLAMA_BASE_URL = ollamaUrl;
          ENABLE_RAG_HYBRID_SEARCH = "true";
          ENABLE_CODE_EXECUTION = "true";
          CODE_EXECUTION_ENGINE = "pyodide";
          ENABLE_CODE_INTERPRETER = "true";
          CODE_INTERPRETER_ENGINE = "pyodide";
          ENABLE_PYODIDE_FILE_PERSISTENCE = "false";
          ENABLE_CONTEXT_COMPACTION = "true";
          CONTEXT_COMPACTION_MODEL = "lfm2.5:8b-a1b-q4_K_M";
          CONTEXT_COMPACTION_TOKEN_THRESHOLD = "24000";
          CONTEXT_COMPACTION_TOKEN_CAP = "32000";
          CONTEXT_COMPACTION_RETENTION_PERCENTAGE = "40";
        };
        autoRemoveOnStop = lib.mkDefault false;
        extraOptions = lib.mkDefault [
          "--restart=unless-stopped"
          "--network-alias=open-webui"
        ];
        volumes = lib.mkDefault [
          "${root}/data:/app/backend/data"
          "/etc/localtime:/etc/localtime:ro"
        ];
        dependsOn = [ "open-terminal" ] ++ lib.optional localSearch.enabled "searxng";
        networks = lib.mkDefault [ "traefik" ];
      };
    })
  ];
}
