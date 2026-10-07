# nix-instantiate --eval --strict tests/ollama.nix \
#   --arg nixpkgs /path/to/nixpkgs --arg homeManager /path/to/home-manager
{
  nixpkgs,
  homeManager,
  system ? builtins.currentSystem,
}:
let
  t = import ./lib.nix { inherit nixpkgs homeManager system; };
  inherit (t) lib pkgs;
  ps = import ../modules/public-services/lib.nix { inherit lib; };
  evaluate =
    modules:
    (t.evalSystem {
      users = [ ];
      inherit modules;
    }).config;
  record = ollama: { modules.public-services."chat.example.test" = { inherit ollama; }; };
  base = t.evalSystem { users = [ ]; };
  native = base.config.services.ollama;
  opts = (base.options.modules.public-services.type.nestedTypes.elemType.getSubOptions [ ]).ollama;
  fields = [
    "package"
    "home"
    "modelsDir"
    "listenAddress"
    "port"
    "loadModels"
    "environmentVariables"
  ];
  nativeField = field: if field == "listenAddress" then "host" else field;
  owner = {
    enable = true;
    host = "nixos";
  };
  support = {
    modules.swarm = {
      role = "manager";
      advertiseAddress = "192.0.2.1";
      networkSubnet = "10.251.0.0/24";
      networkGateway = "10.251.0.1";
    };
    modules.open-terminal = {
      dataDir = "/srv/existing-terminal";
      environmentFile = "/run/credentials/terminal.env";
      uid = 1300;
      gid = 1301;
    };
    modules.public-services."search.example.test".searxng = {
      enable = true;
      host = "remote";
      deploy = false;
    };
  };
  ui = owner // {
    webui = true;
    dataDir = "/srv/existing-webui";
    # Consumer route is independent of the native bind address.
    ollamaUrl = "http://consumer-route.example.test:11500";
  };
  customInput = {
    package = pkgs.ollama-vulkan;
    home = "/srv/existing-ollama";
    modelsDir = "/srv/existing-model-store";
    listenAddress = "192.0.2.1";
    port = 11435;
    loadModels = [
      "embeddinggemma"
      "qwen3-vl:4b-instruct"
    ];
    environmentVariables = {
      OLLAMA_VULKAN = "1";
      OLLAMA_CONTEXT_LENGTH = "16384";
    };
  };
  defaults = evaluate [ (record owner) ];
  backendOnly = evaluate [ (record (owner // customInput)) ];
  local = evaluate [
    support
    (record (ui // customInput))
  ];
  homeOnly = evaluate [ (record (owner // { home = "/srv/other-ollama"; })) ];
  overrides = evaluate [
    (record (owner // customInput))
    {
      services.ollama = {
        package = pkgs.ollama-cpu;
        home = "/srv/native-ollama";
        modelsDir = "/srv/native-model-store";
        host = "127.0.0.2";
        port = 11436;
        loadModels = [ "consumer-model" ];
        environmentVariables = {
          OLLAMA_CONTEXT_LENGTH = "8192";
          OLLAMA_VULKAN = "0";
          CONSUMER_VALUE = "kept";
        };
        openFirewall = false;
        syncModels = true;
      };
      systemd.services.ollama.serviceConfig = {
        Restart = "always";
        RestartSec = "9s";
      };
    }
  ];
  nativeHome = evaluate [
    (record (owner // { home = "/srv/shared-default"; }))
    { services.ollama.home = "/srv/native-home"; }
  ];
  inactive = map (entry: evaluate [ (record (customInput // { webui = true; } // entry)) ]) [
    {
      enable = false;
      host = "nixos";
    }
    {
      enable = true;
      host = "remote";
    }
    {
      enable = true;
      host = "nixos";
      deploy = false;
    }
  ];
  duplicate = evaluate [
    (record owner)
    { modules.public-services."second.example.test".ollama = owner; }
  ];
  missing =
    map
      (
        extra:
        builtins.tryEval (
          builtins.deepSeq
            (evaluate [
              support
              (record ui)
              extra
            ]).virtualisation.oci-containers.containers
            true
        )
      )
      [
        (record { dataDir = lib.mkForce null; })
        (record { ollamaUrl = lib.mkForce null; })
        { modules.open-terminal.environmentFile = lib.mkForce null; }
        { modules.public-services."search.example.test".searxng.enable = lib.mkForce false; }
      ];
  obsolete = map (input: builtins.tryEval (builtins.deepSeq (evaluate [ input ]).modules true)) [
    { modules.ollama.enable = true; }
    { modules.public-services."old.example.test".open-webui.enable = true; }
  ];
  nativeInput = {
    services.ollama = {
      enable = true;
      home = "/srv/standalone-ollama";
    };
  };
  nativeOnly = evaluate [ nativeInput ];
  standardNative =
    (import "${toString nixpkgs}/nixos/lib/eval-config.nix" {
      inherit system;
      modules = [ nativeInput ];
    }).config;
  valid = cfg: lib.all (a: a.assertion) cfg.assertions;
  noUi =
    cfg:
    !cfg.modules.docker.enable
    && !cfg.modules.swarm.enable
    && !cfg.modules.open-terminal.enable
    && cfg.virtualisation.oci-containers.containers == { }
    && !(cfg.systemd.services ? docker-open-webui);
  container = local.virtualisation.oci-containers.containers.open-webui;
  route = lib.findFirst (r: r.service == "ollama") null (ps.routes local);
in
assert !(base.options.modules ? ollama) && !(base.options.modules ? open-webui);
assert lib.all (result: !result.success) obsolete;
assert !opts.enable.default && !opts.webui.default && opts.webui.type.check true;
assert !opts.webui.type.check "true";
assert
  builtins.attrNames opts == [
    "dataDir"
    "deploy"
    "enable"
    "environmentVariables"
    "home"
    "host"
    "listenAddress"
    "loadModels"
    "modelsDir"
    "ollamaUrl"
    "package"
    "port"
    "private"
    "webui"
  ];
assert lib.all (
  field:
  opts.${field}.type.name == base.options.services.ollama.${nativeField field}.type.name
  && opts.${field}.description == base.options.services.ollama.${nativeField field}.description
  && opts.${field}.default == base.options.services.ollama.${nativeField field}.default
  &&
    defaults.modules.public-services."chat.example.test".ollama.${field} == native.${nativeField field}
) fields;
assert !opts.port.type.check 65536 && !opts.port.type.check "11434";
assert !opts.package.type.check "ollama" && !opts.listenAddress.type.check 1;
assert !opts.home.type.check 1 && !opts.modelsDir.type.check 1;
assert !opts.loadModels.type.nestedTypes.elemType.check 1;
assert !opts.environmentVariables.type.nestedTypes.elemType.check 1;
assert lib.all (
  cfg:
  valid cfg
  && !(ps.select cfg "ollama").enabled
  && !cfg.services.ollama.enable
  && noUi cfg
  && cfg.services.ollama.home == native.home
  && cfg.services.ollama.modelsDir == native.modelsDir
  && cfg.services.ollama.environmentVariables == native.environmentVariables
  && cfg.services.ollama.loadModels == [ ]
  && !cfg.services.ollama.openFirewall
  && !(cfg.systemd.services ? ollama)
  && !(cfg.systemd.services ? ollama-model-loader)
) ([ base.config ] ++ inactive);
assert valid defaults && valid backendOnly && valid local;
assert (ps.select backendOnly "ollama").enabled && backendOnly.services.ollama.enable;
assert !backendOnly.modules.public-services."chat.example.test".ollama.webui;
assert noUi defaults && noUi backendOnly && backendOnly.home-manager.users == { };
assert ps.routes backendOnly == [ ] && ps.hosts backendOnly ? "chat.example.test";
assert
  map (cfg: builtins.length (ps.routes cfg)) inactive == [
    0
    1
    1
  ];
assert route.hostname == "chat.example.test" && route.service == "ollama";
assert route.cfg.backendUrl == "http://open-webui:8080";
assert lib.any (
  a: !a.assertion && lib.hasInfix "only one local ollama" a.message
) duplicate.assertions;
assert lib.all (result: !result.success) missing;
assert local.services.ollama.enable && local.modules.docker.enable && local.modules.swarm.enable;
assert local.modules.open-terminal.enable && local.home-manager.users == { };
assert defaults.services.ollama.home == "/var/lib/ollama";
assert defaults.services.ollama.modelsDir == "/var/lib/ollama/models";
assert defaults.services.ollama.host == "127.0.0.1" && defaults.services.ollama.port == 11434;
assert
  defaults.services.ollama.loadModels == [ ] && !(defaults.systemd.services ? ollama-model-loader);
assert
  defaults.services.ollama.environmentVariables == {
    OLLAMA_NO_CLOUD = "1";
    OLLAMA_CONTEXT_LENGTH = "32768";
    OLLAMA_NUM_PARALLEL = "1";
    OLLAMA_KEEP_ALIVE = "10m";
  };
assert defaults.services.ollama.openFirewall && !defaults.services.ollama.syncModels;
assert homeOnly.services.ollama.modelsDir == "/srv/other-ollama/models";
assert nativeHome.services.ollama.modelsDir == "/srv/native-home/models";
assert lib.all (field: backendOnly.services.ollama.${nativeField field} == customInput.${field}) (
  lib.remove "environmentVariables" fields
);
assert backendOnly.services.ollama.environmentVariables.OLLAMA_CONTEXT_LENGTH == "16384";
assert backendOnly.services.ollama.environmentVariables.OLLAMA_VULKAN == "1";
assert backendOnly.services.ollama.environmentVariables.OLLAMA_NO_CLOUD == "1";
assert lib.elem 11435 backendOnly.networking.firewall.allowedTCPPorts;
assert
  backendOnly.systemd.services.ollama.unitConfig.RequiresMountsFor == [
    "/srv/existing-ollama"
    "/srv/existing-model-store"
  ];
assert backendOnly.systemd.services.ollama.serviceConfig.Restart == "on-failure";
assert backendOnly.systemd.services.ollama.serviceConfig.RestartSec == "5s";
assert lib.elem "network-online.target" backendOnly.systemd.services.ollama.wants;
assert lib.elem "network-online.target" backendOnly.systemd.services.ollama.after;
assert backendOnly.systemd.services.ollama-model-loader.bindsTo == [ "ollama.service" ];
assert lib.all
  (
    unit:
    lib.elem unit local.systemd.services.docker-open-webui.wants
    && lib.elem unit local.systemd.services.docker-open-webui.after
  )
  [
    "docker-network-traefik.service"
    "ollama.service"
    "ollama-model-loader.service"
  ];
assert container.environment.OLLAMA_BASE_URL == ui.ollamaUrl;
assert container.environment.RAG_OLLAMA_BASE_URL == ui.ollamaUrl;
assert container.environmentFiles == [ "/run/credentials/terminal.env" ];
assert
  container.volumes == [
    "/srv/existing-webui/data:/app/backend/data"
    "/etc/localtime:/etc/localtime:ro"
  ];
assert
  local.systemd.services.docker-open-webui.unitConfig.RequiresMountsFor == [
    "/srv/existing-webui"
    "/run/credentials/terminal.env"
  ];
assert overrides.services.ollama.package == pkgs.ollama-cpu;
assert overrides.services.ollama.home == "/srv/native-ollama";
assert overrides.services.ollama.modelsDir == "/srv/native-model-store";
assert overrides.services.ollama.host == "127.0.0.2" && overrides.services.ollama.port == 11436;
assert overrides.services.ollama.loadModels == [ "consumer-model" ];
assert overrides.services.ollama.environmentVariables.OLLAMA_CONTEXT_LENGTH == "8192";
assert overrides.services.ollama.environmentVariables.OLLAMA_VULKAN == "0";
assert overrides.services.ollama.environmentVariables.CONSUMER_VALUE == "kept";
assert overrides.services.ollama.environmentVariables.OLLAMA_NO_CLOUD == "1";
assert !overrides.services.ollama.openFirewall && overrides.services.ollama.syncModels;
assert
  overrides.systemd.services.ollama.unitConfig.RequiresMountsFor == [
    "/srv/native-ollama"
    "/srv/native-model-store"
  ];
assert overrides.systemd.services.ollama.serviceConfig.Restart == "always";
assert overrides.systemd.services.ollama.serviceConfig.RestartSec == "9s";
assert nativeOnly.services.ollama.enable && noUi nativeOnly;
assert lib.all
  (field: nativeOnly.services.ollama.${field} == standardNative.services.ollama.${field})
  (
    (map nativeField fields)
    ++ [
      "enable"
      "openFirewall"
      "syncModels"
      "user"
      "group"
      "rocmOverrideGfx"
    ]
  );
assert
  nativeOnly.systemd.services.ollama.environment
  == standardNative.systemd.services.ollama.environment;
assert nativeOnly.systemd.services.ollama.after == standardNative.systemd.services.ollama.after;
assert nativeOnly.systemd.services.ollama.wants == standardNative.systemd.services.ollama.wants;
assert
  nativeOnly.systemd.services.ollama.unitConfig == standardNative.systemd.services.ollama.unitConfig;
assert
  nativeOnly.systemd.services.ollama.serviceConfig
  == standardNative.systemd.services.ollama.serviceConfig;
true
