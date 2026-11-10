{
  config,
  lib,
  ...
}:
let
  ps = import ./lib.nix { inherit lib; };
  inherit (lib) mkOption types;
  hosts = ps.hosts config;
  routes = ps.routes config;
  validHostname =
    name:
    builtins.stringLength name <= 253
    && builtins.match "[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+" name != null
    && lib.all (label: builtins.stringLength label <= 63) (lib.splitString "." name);
  paseo = ps.select config "paseo";
  localContainers = lib.filterAttrs (
    _: container: lib.elem "local-services" container.networks
  ) config.virtualisation.oci-containers.containers;
in
{
  options.modules.public-services = mkOption {
    type = types.attrsOf (
      types.submodule {
        options = {
          ssh = ps.common "an SSH endpoint" // {
            private = mkOption {
              type = types.bool;
              default = true;
              description = "Keep this endpoint out of public CNAME records.";
            };
            address = mkOption {
              type = types.nullOr types.nonEmptyStr;
              default = null;
              description = "Address that modules.dns and Headscale MagicDNS records return for this hostname; required when enabled.";
            };
            user = mkOption {
              type = types.nullOr types.nonEmptyStr;
              default = null;
              description = "SSH client login name; does not create a user or grant server access.";
            };
          };
          paseo = ps.common "the shared Paseo user daemon" // {
            environmentFile = ps.pathOption "Runtime environment file; null retains the existing per-user ~/paseo/daemon.env location.";
          };
        };
      }
    );
    default = { };
    description = "Service registry keyed by fully qualified hostname. Every OS of the fleet imports the same registry; a service deploys only on the host named by its `host`, and the gateway, DNS and CNAME modules derive their records from the enabled entries.";
  };

  config = lib.mkMerge [
    {
      # Every module takes public-services/lib.nix as the `ps` argument instead of importing it.
      # Home Manager modules cannot reach NixOS module arguments, so supply it there as well.
      _module.args.ps = ps;
      home-manager.sharedModules = [ { _module.args.ps = ps; } ];
      assertions =
        paseo.assertions
        ++ lib.mapAttrsToList (hostname: _: {
          assertion = validHostname hostname;
          message = "modules.public-services: '${hostname}' must be a fully qualified DNS hostname with valid labels.";
        }) config.modules.public-services
        ++ lib.concatLists (
          lib.mapAttrsToList (
            hostname: services:
            lib.concatLists (
              lib.mapAttrsToList (service: cfg: [
                {
                  assertion = cfg.privateExtraNetworks == [ ] || cfg.private;
                  message = "modules.public-services.${hostname}.${service}.privateExtraNetworks requires private = true.";
                }
                {
                  assertion = !cfg.enable || cfg.host != null;
                  message = "modules.public-services.${hostname}.${service}.host must name the owner machine when enabled.";
                }
                {
                  assertion =
                    !cfg.enable || !(cfg ? backendUrl) || (service == "ollama" && !cfg.webui) || cfg.backendUrl != null;
                  message = "modules.public-services.${hostname}.${service}: HTTP services require backendUrl (the gateway upstream and owner publish address).";
                }
              ]) services
            )
          ) hosts
        )
        ++ lib.mapAttrsToList (hostname: _: {
          assertion = builtins.length (lib.filter (route: route.hostname == hostname) routes) <= 1;
          message = "modules.public-services.${hostname}: only one HTTP backend may be enabled for a hostname.";
        }) hosts
        ++ map (route: {
          assertion = builtins.match "https?://[^[:space:]]+" route.cfg.backendUrl != null;
          message = "modules.public-services.${route.hostname}.${route.service}.backendUrl must be an HTTP(S) upstream URL.";
        }) routes
        ++ lib.mapAttrsToList (backend: matching: {
          assertion = builtins.length (lib.unique (map (route: route.cfg.private) matching)) <= 1;
          message = "modules.public-services: the same HTTP backend '${backend}' cannot have both public and private aliases.";
        }) (lib.groupBy (route: route.cfg.backendUrl) routes)
        ++ map (entry: {
          assertion = entry.cfg.address != null;
          message = "modules.public-services.${entry.hostname}.ssh.address is required when enabled.";
        }) (ps.entries config "ssh");
    }
    (lib.mkIf (localContainers != { }) {
      modules.docker.networks.local-services = { };
    })
    (lib.mkIf (lib.any (entry: ps.isLocal config entry.cfg) (ps.entries config "ssh")) {
      modules.openssh.enable = true;
    })
    (lib.mkIf paseo.enabled {
      modules.paseo = {
        enable = true;
        hostname = paseo.hostname;
        environmentFile = paseo.cfg.environmentFile;
      };
      assertions = [
        {
          assertion = builtins.length (builtins.attrNames config.home-manager.users) == 1;
          message = "A local public Paseo deployment needs exactly one Home Manager user; the existing daemon uses a fixed port.";
        }
      ];
    })
  ];
}
