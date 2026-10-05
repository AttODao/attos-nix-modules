{ config, lib, ... }:
let
  ps = import ../public-services/lib.nix { inherit lib; };
  s = ps.select config "open-webui";
  root = ps.require "open-webui" "dataDir" s.cfg.dataDir;
  environmentFile =
    ps.require "open-webui" "environmentFile or modules.open-terminal.environmentFile"
      (
        if s.cfg.environmentFile != null then
          s.cfg.environmentFile
        else
          config.modules.open-terminal.environmentFile
      );
  ollamaUrl = ps.require "open-webui" "ollamaUrl" s.cfg.ollamaUrl;
  searchEntries = ps.entries config "searxng";
  searxngUrl = ps.require "open-webui" "searxngUrl (or exactly one enabled SearXNG hostname)" (
    if s.cfg.searxngUrl != null then
      s.cfg.searxngUrl
    else if builtins.length searchEntries == 1 then
      "${lib.removeSuffix "/" (builtins.head searchEntries).cfg.backendUrl}/search"
    else
      null
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
    ps.common "Open WebUI" "http://open-webui:8080"
    // {
      dataDir = ps.pathOption "Service root containing the existing data directory and persistent authentication state.";
      environmentFile = ps.pathOption "Runtime Open WebUI environment file; defaults to modules.open-terminal.environmentFile.";
      ollamaUrl = lib.mkOption {
        type = lib.types.nullOr lib.types.nonEmptyStr;
        default = null;
        description = "Consumer-selected Ollama HTTP endpoint reachable from the container; the consumer configures the native listener/network.";
      };
      searxngUrl = lib.mkOption {
        type = lib.types.nullOr lib.types.nonEmptyStr;
        default = null;
        description = "SearXNG query URL reachable from the container. If unset, use the backendUrl plus /search of the sole enabled SearXNG registry entry (local or remote).";
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
      modules.open-terminal.allowedOrigins = lib.mkDefault "https://${s.hostname}";

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
        environmentFiles = [ environmentFile ];
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
        autoRemoveOnStop = false;
        extraOptions = [
          "--restart=unless-stopped"
          "--network-alias=open-webui"
        ];
        volumes = [
          "${root}/data:/app/backend/data"
          "/etc/localtime:/etc/localtime:ro"
        ];
        dependsOn = [ "open-terminal" ] ++ lib.optional localSearch.enabled "searxng";
        networks = [ "traefik" ];
      };
    })
  ];
}
