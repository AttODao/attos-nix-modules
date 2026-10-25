{
  config,
  lib,
  ps,
  ...
}:
let
  s = ps.select config "searxng";
  environmentFile = ps.require "searxng" "environmentFile" s.cfg.environmentFile;
  listen = ps.listen s 8081;
in
{
  options.modules = ps.moduleOptions "searxng" (
    ps.common "SearXNG search service"
    // {
      environmentFile = ps.pathOption "Runtime SearXNG environment file supplying SEARXNG_SECRET; the service refuses to start without it.";
      limiter = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable the SearXNG rate limiter and bot protection with a local Valkey/Redis socket. Disabling it exposes the instance to scraping; standalone instances may keep it off because only loopback can reach them.";
      };
      trustedProxies = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Reverse proxy addresses/CIDRs whose X-Forwarded-For/X-Real-IP the limiter trusts to find the client address (for example the gateway address the proxy connects from). Loopback stays trusted.";
      };
      passNetworks = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Client addresses/CIDRs exempt from the limiter and bot detection (for example a trusted automation host). Grants unlimited API access; keep it narrow.";
      };
    }
  );

  config = lib.mkMerge [
    { assertions = s.assertions; }
    (lib.mkIf s.enabled {
      assertions = [
        {
          assertion = s.cfg.limiter || (s.cfg.trustedProxies == [ ] && s.cfg.passNetworks == [ ]);
          message = "searxng.trustedProxies and searxng.passNetworks require searxng.limiter to be enabled.";
        }
      ];
      services.searx = {
        enable = true;
        inherit environmentFile;
        redisCreateLocally = s.cfg.limiter;
        limiterSettings = lib.mkIf (
          s.cfg.limiter && (s.cfg.trustedProxies != [ ] || s.cfg.passNetworks != [ ])
        ) (lib.mapAttrsRecursive (_: lib.mkDefault) {
          # SearXNGは同梱のlimiter.tomlの既定値にこの設定をdeep mergeする。
          botdetection = {
            trusted_proxies = [
              "127.0.0.0/8"
              "::1"
            ] ++ s.cfg.trustedProxies;
            ip_lists.pass_ip = s.cfg.passNetworks;
          };
        });
        settings = lib.mapAttrsRecursive (_: lib.mkDefault) {
          # These default engines require Tor, which this deployment does not provide.
          use_default_settings.engines.remove = [
            "ahmia"
            "torch"
          ];
          general = {
            debug = false;
            instance_name = "AttODao Search";
          };
          search = {
            safe_search = 1;
            autocomplete = "";
            default_lang = "all";
            formats = [
              "html"
              "json"
            ];
          };
          server = {
            base_url = "${ps.url s 8081}/";
            bind_address = listen.address;
            port = listen.port;
            # searx-init substitutes the environment file value; the start check below rejects an unset one.
            secret_key = "$SEARXNG_SECRET";
            limiter = s.cfg.limiter;
            image_proxy = true;
          };
        };
      };
      networking.firewall = ps.backendFirewall config s [ ];
      systemd.services.searx-init = {
        unitConfig.RequiresMountsFor = [ environmentFile ];
        # An empty secret would be substituted silently; fail before the settings file is generated.
        preStart = ''
          : "''${SEARXNG_SECRET:?SEARXNG_SECRET must be set in ${environmentFile}}"
        '';
      };
      systemd.services.searx = {
        unitConfig.RequiresMountsFor = [ environmentFile ];
        inherit (ps.afterNetworkOnline) wants after;
      };
    })
  ];
}
