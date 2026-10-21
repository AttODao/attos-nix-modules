{ lib }:
let
  inherit (lib) mkOption types;
  # Services whose HTTP upstream the consumer supplies as backendUrl; the owner publishes it there.
  httpServices = [
    "forgejo"
    "immich"
    "attos-hoyo-dashboard"
    "karakeep"
    "vaultwarden"
    "opencloud"
    "jellyfin"
    "ollama"
    "searxng"
  ];
  upstream = _: cfg: cfg.backendUrl or null;
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
            // lib.optionalAttrs (lib.elem service httpServices) {
              backendUrl = mkOption {
                type = types.nullOr types.nonEmptyStr;
                default = null;
                description = "HTTP upstream reachable by the gateway, with an explicit port (for example http://10.250.0.2:3000); required when enabled. The owner publishes the service on this address and port.";
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
        "sshAddresses"
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

  # Local Docker bridge shared by the containers of one service (and its same-host clients).
  network = selected: if selected.standalone then "local-services" else "backend-${selected.service}";
  networkUnit = selected: "docker-network-${network selected}.service";
  url =
    selected: port:
    if selected.standalone then
      "http://${selected.hostname}:${toString port}"
    else
      "https://${selected.hostname}";

  # Host address and port of an http://address:port upstream.
  backendEndpoint =
    selected:
    let
      parts = builtins.match "https?://([^/:]+|[[][^]]+[]]):([0-9]+)/?" (
        require selected.service "backendUrl" selected.cfg.backendUrl
      );
    in
    if parts == null then
      throw "${selected.service}: backendUrl must be http://<address>:<port> so the owner can publish it."
    else
      {
        address = builtins.head parts;
        port = builtins.elemAt parts 1;
      };
  # Standalone stays on loopback; a public owner publishes on its backendUrl for the gateway.
  # Native services bind this address (IPv6 literal without brackets) and integer port.
  listen =
    selected: defaultPort:
    let
      endpoint =
        if selected.standalone then
          {
            address = "127.0.0.1";
            port = toString defaultPort;
          }
        else
          backendEndpoint selected;
    in
    {
      address = lib.removeSuffix "]" (lib.removePrefix "[" endpoint.address);
      port = lib.toInt endpoint.port;
    };
  # A public owner binds the backendUrl address, which must exist first.
  afterNetworkOnline = {
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
  };
  # Standalone stays on loopback; a public owner publishes on its backendUrl for the gateway.
  # A native owner listens itself, so admit the gateway to the backendUrl port on that address only.
  backendFirewall =
    config: selected: extraPorts:
    let
      endpoint = backendEndpoint selected;
      ports = [ endpoint.port ] ++ map toString extraPorts;
    in
    lib.mkIf (!selected.standalone && !lib.hasPrefix "127." endpoint.address) (
      if config.networking.nftables.enable then
        {
          extraInputRules = lib.concatMapStrings (port: ''
            ip daddr ${endpoint.address} tcp dport ${port} accept
          '') ports;
        }
      else
        {
          extraCommands = lib.concatMapStrings (port: ''
            iptables -A nixos-fw -d ${endpoint.address} -p tcp --dport ${port} -j nixos-fw-accept
          '') ports;
        }
    );
  # Fixed host port for Forgejo SSH on the backendUrl address; the gateway listens on 22.
  forgejoSshBackendPort = 2222;
  publish =
    selected: standalonePort: containerPort:
    let
      endpoint = backendEndpoint selected;
    in
    if selected.standalone then
      [ "127.0.0.1:${toString standalonePort}:${toString containerPort}" ]
    else
      [ "${endpoint.address}:${endpoint.port}:${toString containerPort}" ];

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
