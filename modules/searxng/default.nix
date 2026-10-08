{
  config,
  lib,
  pkgs,
  ...
}:
let
  ps = import ../public-services/lib.nix { inherit lib; };
  s = ps.select config "searxng";
  environmentFile = ps.require "searxng" "environmentFile" s.cfg.environmentFile;
  settings = (pkgs.formats.yaml { }).generate "searxng-settings.yml" {
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
      bind_address = "0.0.0.0";
      port = 8080;
      secret_key = "overridden-by-SEARXNG_SECRET";
      limiter = false;
      image_proxy = true;
    };
  };
in
{
  imports = [
    ../docker
    ../swarm
  ];

  options.modules = ps.moduleOptions "searxng" (
    ps.common "SearXNG search service"
    // {
      environmentFile = ps.pathOption "Runtime SearXNG environment file supplying SEARXNG_SECRET.";
    }
  );

  config = lib.mkMerge [
    { assertions = s.assertions; }
    (lib.mkIf s.enabled {
      modules.docker.enable = true;
      modules.swarm.enable = lib.mkIf (!s.standalone) true;

      systemd.services.docker-searxng = {
        unitConfig.RequiresMountsFor = [ environmentFile ];
        wants = [ (ps.networkUnit s) ];
        after = [ (ps.networkUnit s) ];
        restartTriggers = [ settings ];
      };
      virtualisation.oci-containers.containers.searxng = {
        image = lib.mkDefault "searxng/searxng:2026.10.4-d48c4b555";
        ports = lib.mkDefault (lib.optional s.standalone "127.0.0.1:8081:8080");
        environmentFiles = lib.mkDefault [ environmentFile ];
        environment = lib.mapAttrs (_: lib.mkDefault) {
          FORCE_OWNERSHIP = "false";
          SEARXNG_BASE_URL = "${ps.url s 8081}/";
          SEARXNG_BIND_ADDRESS = "0.0.0.0";
          SEARXNG_LIMITER = "false";
          SEARXNG_PORT = "8080";
          SEARXNG_SETTINGS_PATH = "/etc/searxng/settings.yml";
        };
        autoRemoveOnStop = lib.mkDefault false;
        extraOptions = lib.mkDefault [
          "--restart=unless-stopped"
          "--network-alias=searxng"
          "--cap-drop=ALL"
          "--cap-add=CHOWN"
          "--cap-add=SETGID"
          "--cap-add=SETUID"
          "--cap-add=DAC_OVERRIDE"
          "--security-opt=no-new-privileges:true"
        ];
        volumes = lib.mkDefault [
          "${settings}:/etc/searxng/settings.yml:ro"
          "/etc/localtime:/etc/localtime:ro"
        ];
        networks = lib.mkDefault [ (ps.network s) ];
      };
    })
  ];
}
