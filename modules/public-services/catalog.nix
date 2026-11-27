{
  config,
  lib,
  ps,
  ...
}:
# Monitoring and operation catalog of the public service kinds.
#
# Every service kind module declares ONCE, in modules.service-catalog.kinds.<kind>, what a
# dashboard shows for one of its registry entries (title, icon kind, systemd units, permitted
# operations, reachability probe, start variants). Two consumers are generated from it:
#   - ps.catalog config: one service per registry hostname (HyperMonitor's [[services]]),
#   - the attos-deck-agent allow-list of the host that runs the units (below).
# Adding or removing a registry entry therefore adds or removes the service in both places.
let
  inherit (lib) mkOption types;
  cfg = config.modules.service-catalog;
  unitName = types.strMatching "[A-Za-z0-9@_.:-]+\\.(service|socket|timer|target|path|mount)";
  op = types.enum [
    "start"
    "stop"
    "restart"
  ];
  variant = types.submodule {
    options = {
      id = mkOption {
        type = types.strMatching "[A-Za-z0-9_.-]+";
        description = "Stable identifier the dashboard sends back when starting this variant.";
      };
      label = mkOption {
        type = types.nonEmptyStr;
        description = "Name shown in the start choice.";
      };
      unit = mkOption {
        type = unitName;
        description = "Unit that runs this variant (at most one variant runs at a time).";
      };
    };
  };
  common = {
    title = mkOption {
      type = types.nonEmptyStr;
      description = "Display title.";
    };
    units = mkOption {
      type = types.listOf unitName;
      default = [ ];
      description = "systemd units whose state the dashboard shows and that the permitted operations act on.";
    };
    ops = mkOption {
      type = types.listOf op;
      default = [ "restart" ];
      description = "Permitted operations on the units (and on the variants' units).";
    };
    variants = mkOption {
      type = types.listOf variant;
      default = [ ];
      description = "Alternatives to choose from when starting (each with its own unit), for services such as Strata.";
    };
  };
  entry = types.submodule {
    options = common // {
      kind = mkOption {
        type = types.nullOr types.nonEmptyStr;
        default = null;
        description = "Icon kind for the dashboard; null uses the registry service kind name.";
      };
      probe = mkOption {
        type = types.nullOr (types.strMatching "/[^[:space:]]*");
        default = "/";
        description = "Path on https://<hostname> fetched as the reachability check (status and certificate); null for none. Ignored when the hostname has no HTTP route.";
      };
      order = mkOption {
        type = types.int;
        default = 100;
        description = "When several kinds share one hostname they form one service: units, operations and variants are merged, and the title, icon and probe come from the kind with the lowest order.";
      };
    };
  };
  target = types.submodule {
    options = common // {
      id = mkOption {
        type = types.strMatching "[A-Za-z0-9][A-Za-z0-9_.-]*";
        description = "Unique service id (registry services use their hostname).";
      };
      kind = mkOption {
        type = types.nonEmptyStr;
        default = "system";
        description = "Icon kind for the dashboard.";
      };
      host = mkOption {
        type = types.nonEmptyStr;
        description = "networking.hostName of the machine that runs the units (as `host` in the registry).";
      };
      url = mkOption {
        type = types.nullOr (types.strMatching "https?://[^[:space:]]+");
        default = null;
        description = "Link shown for the target; null for none.";
      };
      probe = mkOption {
        type = types.nullOr (types.strMatching "https?://[^[:space:]]+");
        default = null;
        description = "Reachability check URL; null for none.";
      };
    };
  };

  # Units of this host's catalogued services with the operations the agent may run on them.
  localUnits = lib.filter (s: s.host == config.networking.hostName) (ps.catalog config);
  allow =
    s:
    map (unit: {
      ${unit}.allow = s.ops ++ [ "status" ];
    }) (s.units ++ map (v: v.unit) s.variants);
  agentUnits = lib.zipAttrsWith (_: values: {
    allow = lib.unique (lib.concatMap (v: v.allow) values);
  }) (lib.concatMap allow localUnits);
in
{
  options.modules.service-catalog = {
    kinds = mkOption {
      type = types.attrsOf (types.functionTo entry);
      default = { };
      description = "Per service kind (the attribute names under modules.public-services.<hostname>): a function from a registry entry `{ hostname, cfg }` to what a dashboard shows and may do. Set by each kind's module; kinds without a declaration are not catalogued (SSH endpoints, aliases).";
    };
    extraTargets = mkOption {
      type = types.listOf target;
      default = [ ];
      example = [
        {
          id = "traefik";
          title = "Traefik";
          host = "gateway";
          units = [ "traefik.service" ];
        }
      ];
      description = "Targets that are not in the registry (infrastructure units). Like registry services they appear in ps.catalog and widen the agent allow-list on `host`; declare them where both the dashboard host and the owner host read them.";
    };
    agentAllow = mkOption {
      type = types.bool;
      default = true;
      description = "Add `status` and the permitted operations of every catalogued unit owned by this host to the attos-deck-agent allow-list (when the agent is enabled).";
    };
  };

  config = lib.mkIf (cfg.agentAllow && config.modules.attos-deck.agent.enable) {
    modules.attos-deck.agent.settings.units = agentUnits;
  };
}
