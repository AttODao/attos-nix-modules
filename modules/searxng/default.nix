{
  config,
  lib,
  ...
}:
let
  ps = import ../public-services/lib.nix { inherit lib; };
  s = ps.select config "searxng";
  environmentFile = ps.require "searxng" "environmentFile" s.cfg.environmentFile;
  listen =
    if s.standalone then
      {
        address = "127.0.0.1";
        port = "8081";
      }
    else
      ps.backendEndpoint s;
in
{
  options.modules = ps.moduleOptions "searxng" (
    ps.common "SearXNG search service"
    // {
      environmentFile = ps.pathOption "Runtime SearXNG environment file supplying SEARXNG_SECRET.";
    }
  );

  config = lib.mkMerge [
    { assertions = s.assertions; }
    (lib.mkIf s.enabled {
      services.searx = {
        enable = true;
        inherit environmentFile;
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
            bind_address = lib.removeSuffix "]" (lib.removePrefix "[" listen.address);
            port = lib.toInt listen.port;
            # SEARXNG_SECRET from the environment file overrides this placeholder.
            secret_key = "overridden-by-SEARXNG_SECRET";
            limiter = false;
            image_proxy = true;
          };
        };
      };
      networking.firewall = ps.backendFirewall config s;
      systemd.services.searx = {
        unitConfig.RequiresMountsFor = [ environmentFile ];
        # A public owner binds the backendUrl address, which must exist first.
        wants = [ "network-online.target" ];
        after = [ "network-online.target" ];
      };
    })
  ];
}
