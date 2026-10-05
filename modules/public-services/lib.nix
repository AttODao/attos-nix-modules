{ lib }:
let
  inherit (lib) mkOption types;
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
          options.${service} = options;
        }
      );
    };

  common =
    description: backendUrl:
    {
      enable = lib.mkEnableOption description;
      deploy = mkOption {
        type = types.bool;
        default = true;
        description = "Run this service on this machine. Set false to register a remote backend without deploying it here.";
      };
      private = mkOption {
        type = types.bool;
        default = false;
        description = "Exclude this hostname from public CNAMEs and restrict HTTP access to the configured private networks.";
      };
    }
    // lib.optionalAttrs (backendUrl != null) {
      backendUrl = mkOption {
        type = types.nonEmptyStr;
        default = backendUrl;
        description = "HTTP upstream reachable by Traefik; override for a remote or native backend.";
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
        lib.mapAttrsToList (service: cfg: { inherit hostname service cfg; }) (
          lib.filterAttrs (_: cfg: (cfg.enable or false) && (cfg.backendUrl or null) != null) services
        )
      ) (hosts config)
    );

  select =
    config: service:
    let
      local = lib.filter (entry: entry.cfg.deploy) (entries config service);
      first = if local == [ ] then null else builtins.head local;
    in
    {
      enabled = first != null;
      hostname = if first == null then null else first.hostname;
      cfg = if first == null then { } else first.cfg;
      # ponytail: legacy units/container names are single-instance; use instance-qualified names when multiple local deployments are needed.
      assertions = [
        {
          assertion = builtins.length local <= 1;
          message = "modules.public-services: only one local ${service} deployment is supported; use deploy = false for remote hosts.";
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
