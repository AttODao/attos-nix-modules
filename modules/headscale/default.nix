{
  config,
  lib,
  pkgs,
  ps,
  ...
}:
let
  s = ps.select config "headscale";
  inherit (lib) mkOption types;
  json = pkgs.formats.json { };
  listen = ps.listen s 8080;
  baseDomain = ps.require "headscale" "baseDomain" s.cfg.baseDomain;
  # Tailnet clients resolve every other registered hostname through the consumer's resolver. The control
  # hostname stays on the client's own DNS: the client dials it outside the tunnel, so a tailnet-only
  # answer would be unreachable.
  splitHostnames = lib.filter (hostname: hostname != s.hostname) (
    builtins.attrNames (ps.hosts config)
  );
in
{
  options.modules = ps.moduleOptions "headscale" (
    ps.common "Headscale coordination server for Tailscale clients"
    // {
      baseDomain = mkOption {
        type = types.nullOr (
          types.strMatching "[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+"
        );
        default = null;
        example = "tail.example.org";
        description = "MagicDNS base domain for node names (<node>.<baseDomain>); required when deployed. It must not contain the control hostname.";
      };
      nameservers = mkOption {
        type = types.listOf types.nonEmptyStr;
        default = [ ];
        example = [ "10.0.0.1" ];
        description = "Resolvers that tailnet clients use, as split DNS, for every other modules.public-services hostname; empty leaves those names to the client's own DNS. The consumer routes these addresses into the tailnet (for example as a subnet route) and answers there with addresses reachable through it.";
      };
      policy = mkOption {
        type = types.nullOr json.type;
        default = null;
        example = {
          acls = [
            {
              action = "accept";
              src = [ "*" ];
              dst = [ "*:*" ];
            }
          ];
        };
        description = "Headscale policy (ACLs, autoApprovers) written as a JSON file; null runs without a policy, which allows all traffic and leaves routes to manual approval.";
      };
    }
  );

  config = lib.mkMerge [
    { assertions = s.assertions; }
    (lib.mkIf s.enabled {
      assertions = [
        {
          assertion =
            s.standalone || !(s.hostname == baseDomain || lib.hasSuffix ".${baseDomain}" s.hostname);
          message = "headscale: baseDomain must not contain the control hostname ${s.hostname}.";
        }
      ];
      services.headscale = {
        enable = true;
        inherit (listen) address port;
        settings = {
          server_url = ps.url s 8080;
          # Upstream defaults to 127.0.0.1:9090, which Prometheus also uses by default.
          metrics_listen_addr = lib.mkDefault "127.0.0.1:9098";
          dns = {
            magic_dns = true;
            base_domain = baseDomain;
            override_local_dns = false;
            nameservers.split = lib.mkIf (s.cfg.nameservers != [ ]) (
              lib.genAttrs splitHostnames (_: s.cfg.nameservers)
            );
          };
          policy.path = lib.mkIf (s.cfg.policy != null) (json.generate "headscale-policy.json" s.cfg.policy);
        };
      };
      networking.firewall = ps.backendFirewall config s [ ];
    })
  ];
}
