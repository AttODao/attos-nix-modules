{ lib }:
let
  inherit (lib) mkOption types;
  # OCI service names/ports are implementation constants, not consumer endpoints.
  httpBackends = {
    forgejo = "http://forgejo:3000";
    immich = "http://immich-server:2283";
    karakeep = "http://karakeep:3000";
    vaultwarden = "http://vaultwarden:80";
    opencloud = "http://opencloud:9200";
    jellyfin = "http://jellyfin:8096";
    ollama = "http://open-webui:8080";
    searxng = "http://searxng:8080";
  };
  upstream =
    service: cfg:
    if (cfg.backendUrl or null) != null then
      cfg.backendUrl
    else if cfg.deploy or true then
      httpBackends.${service} or null
    else
      null;
in
rec {
  absolutePath = types.addCheck types.str (
    value:
    lib.hasPrefix "/" value
    && value != builtins.storeDir
    && !lib.isStorePath value
    && lib.all (character: !lib.hasInfix character value) [
      ":"
      "\n"
      "\r"
    ]
  );

  pathOption =
    description:
    mkOption {
      type = types.nullOr absolutePath;
      default = null;
      inherit description;
    };

  option =
    service: options:
    mkOption {
      type = types.attrsOf (
        types.submodule {
          options.${service} =
            options
            // lib.optionalAttrs (builtins.hasAttr service httpBackends) {
              backendUrl = mkOption {
                type = types.nullOr types.nonEmptyStr;
                default = null;
                description = "Explicit HTTP(S) upstream; required for deploy=false endpoints. Null uses the managed OCI DNS backend.";
              };
            };
        }
      );
    };

  # Both entry points share the same typed service inputs; endpoint metadata stays public-only.
  standaloneOptions = serviceOptions: {
    options =
      builtins.removeAttrs serviceOptions [
        "host"
        "deploy"
        "private"
        "backendUrl"
        "backendAddress"
      ]
      // {
        hostname = mkOption {
          type = types.strMatching "[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?";
          default = "localhost";
          description = "Hostname advertised by the standalone service; does not register DNS or a proxy route.";
        };
      };
  };

  moduleOptions = service: serviceOptions: {
    public-services = option service serviceOptions;
    ${service} = mkOption {
      type = types.submodule (standaloneOptions serviceOptions);
      default = { };
      description = "Standalone ${service}; reuses the public service inputs without endpoint registration.";
    };
  };

  network = selected: if selected.standalone then "local-services" else "backend-${selected.service}";
  # Fixed OCI DNS upstreams need an overlay even when their owner is another OS.
  backendNetworks =
    config:
    lib.unique (
      map
        (
          route:
          network {
            standalone = false;
            inherit (route) service;
          }
        )
        (
          lib.filter (route: builtins.hasAttr route.service httpBackends && route.cfg.deploy) (routes config)
        )
    );
  networkUnit = selected: "docker-network-${network selected}.service";
  url =
    selected: port:
    if selected.standalone then
      "http://${selected.hostname}:${toString port}"
    else
      "https://${selected.hostname}";

  common = description: {
    enable = lib.mkEnableOption description;
    host = mkOption {
      type = types.nullOr types.nonEmptyStr;
      default = null;
      description = "Owner's networking.hostName, required when enabled. Every fleet configuration imports the same registry; only this host deploys the service.";
    };
    deploy = mkOption {
      type = types.bool;
      default = true;
      description = "Deploy on the owner host when enabled. False explicitly registers an externally managed endpoint without creating local dependencies or units.";
    };
    private = mkOption {
      type = types.bool;
      default = false;
      description = "Exclude this hostname from public CNAMEs and restrict HTTP access to the configured private networks.";
    };
  };

  entries =
    config: service:
    lib.mapAttrsToList (hostname: host: {
      inherit hostname;
      cfg = host.${service};
    }) (lib.filterAttrs (_: host: host.${service}.enable or false) config.modules.public-services);

  hosts =
    config:
    lib.filterAttrs (
      _: services: lib.any (service: service.enable or false) (lib.attrValues services)
    ) config.modules.public-services;

  routes =
    config:
    lib.concatLists (
      lib.mapAttrsToList (
        hostname: services:
        lib.mapAttrsToList
          (service: cfg: {
            inherit hostname service;
            cfg = cfg // {
              backendUrl = upstream service cfg;
            };
          })
          (
            lib.filterAttrs (
              service: cfg:
              (cfg.enable or false) && (service != "ollama" || cfg.webui) && upstream service cfg != null
            ) services
          )
      ) (hosts config)
    );

  isLocal = config: cfg: cfg.deploy && cfg.host != null && cfg.host == config.networking.hostName;

  select =
    config: service:
    let
      local = lib.filter (entry: isLocal config entry.cfg) (entries config service);
      first = if local == [ ] then null else builtins.head local;
      # SSH is endpoint metadata for openssh; Paseo already has a public-to-global bridge.
      standalone =
        !lib.elem service [
          "ssh"
          "paseo"
        ]
        && (config.modules.${service}.enable or false);
    in
    {
      inherit standalone service;
      enabled = standalone || first != null;
      hostname =
        if standalone then
          config.modules.${service}.hostname
        else if first == null then
          null
        else
          first.hostname;
      cfg =
        if standalone then
          config.modules.${service}
        else if first == null then
          { }
        else
          first.cfg;
      # ponytail: legacy units/container names are single-instance; use instance-qualified names when multiple local deployments are needed.
      assertions = [
        {
          assertion = builtins.length local <= 1;
          message = "modules.public-services: only one local ${service} deployment is supported on ${config.networking.hostName}; use another host or deploy = false for endpoint-only aliases.";
        }
        {
          assertion = !standalone || local == [ ];
          message = "${service}: standalone and public local deployment cannot be enabled together; choose one entry point.";
        }
      ];
    };

  require =
    service: field: value:
    if value == null then
      throw "${service}: ${field} must be supplied when deployed locally."
    else
      value;
}
