{ config, lib, ... }:
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
  externalOptions =
    description:
    ps.common description "http://localhost"
    // {
      deploy = mkOption {
        type = types.bool;
        default = false;
        description = "These guests are configured by their own dotfiles; only forwarding is supported here.";
      };
      backendUrl = mkOption {
        type = types.nullOr types.nonEmptyStr;
        default = null;
        description = "Required HTTP upstream for the externally managed service.";
      };
      insecureSkipVerify = mkOption {
        type = types.bool;
        default = false;
        description = "Explicitly allow an upstream self-signed certificate; retain TLS verification unless needed.";
      };
    };
  paseo = ps.select config "paseo";
in
{
  options.modules.public-services = mkOption {
    type = types.attrsOf (
      types.submodule {
        options = {
          ssh = ps.common "an SSH endpoint" null // {
            deploy = mkOption {
              type = types.bool;
              default = false;
              description = "Enable the local OpenSSH preset rather than registering a remote SSH endpoint.";
            };
            private = mkOption {
              type = types.bool;
              default = true;
              description = "Keep this endpoint out of public CNAME records.";
            };
            address = mkOption {
              type = types.nullOr types.nonEmptyStr;
              default = null;
              description = "Address used for this SSH hostname in the local DNS hosts file.";
            };
            user = mkOption {
              type = types.nullOr types.nonEmptyStr;
              default = null;
              description = "SSH client login name; does not create a user or grant server access.";
            };
            port = mkOption {
              type = types.port;
              default = 22;
              description = "SSH client port; configure the server's standard OpenSSH ports separately.";
            };
          };
          paseo = ps.common "the shared Paseo user daemon" null // {
            environmentFile = ps.pathOption "Runtime environment file; null retains the existing per-user ~/paseo/daemon.env location.";
          };
          code-server = externalOptions "forwarding to a code-server guest";
          sunshine = externalOptions "forwarding to a Sunshine guest";
        };
      }
    );
    default = { };
    description = "Services indexed by their public DNS hostname; configuration is supplied by the consumer.";
  };

  config = lib.mkMerge [
    {
      assertions =
        paseo.assertions
        ++ lib.mapAttrsToList (hostname: _: {
          assertion = validHostname hostname;
          message = "modules.public-services: '${hostname}' must be a fully qualified DNS hostname with valid labels.";
        }) config.modules.public-services
        ++ lib.mapAttrsToList (hostname: services: {
          assertion =
            builtins.length (
              lib.unique (
                map (service: service.private) (lib.filter (service: service.enable) (lib.attrValues services))
              )
            ) <= 1;
          message = "modules.public-services.${hostname}: enabled services must agree on private visibility.";
        }) hosts
        ++ lib.mapAttrsToList (hostname: _: {
          assertion = builtins.length (lib.filter (route: route.hostname == hostname) routes) <= 1;
          message = "modules.public-services.${hostname}: only one HTTP backend may be enabled for a hostname.";
        }) hosts
        ++
          lib.concatMap
            (
              service:
              map (entry: {
                assertion = !entry.cfg.deploy && entry.cfg.backendUrl != null;
                message = "modules.public-services.${entry.hostname}.${service}: supply backendUrl and keep deploy = false; the guest has its own configuration.";
              }) (ps.entries config service)
            )
            [
              "code-server"
              "sunshine"
            ]
        ++ map (route: {
          assertion = builtins.match "https?://[^[:space:]]+" route.cfg.backendUrl != null;
          message = "modules.public-services.${route.hostname}.${route.service}.backendUrl must be an HTTP(S) upstream URL.";
        }) routes
        ++ lib.mapAttrsToList (backend: matching: {
          assertion = builtins.length (lib.unique (map (route: route.cfg.private) matching)) <= 1;
          message = "modules.public-services: the same HTTP backend '${backend}' cannot have both public and private aliases.";
        }) (lib.groupBy (route: route.cfg.backendUrl) routes)
        ++ map (entry: {
          assertion = !config.modules.traefik.enable || entry.cfg.backendUrl != null;
          message = "modules.public-services.${entry.hostname}.groupware.backendUrl is required on the Traefik gateway.";
        }) (ps.entries config "groupware")
        ++ map (entry: {
          assertion = entry.cfg.address != null;
          message = "modules.public-services.${entry.hostname}.ssh.address is required when enabled.";
        }) (ps.entries config "ssh");
    }
    (lib.mkIf (lib.any (entry: entry.cfg.deploy) (ps.entries config "ssh")) {
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
