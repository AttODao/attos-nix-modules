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

  options.modules.public-services = ps.option "searxng" (
    ps.common "SearXNG search service" "http://searxng:8080"
    // {
      environmentFile = ps.pathOption "Runtime SearXNG environment file supplying SEARXNG_SECRET.";
    }
  );

  config = lib.mkMerge [
    { assertions = s.assertions; }
    (lib.mkIf s.enabled {
      modules.docker.enable = true;
      modules.swarm.enable = true;

      systemd.services.docker-searxng = {
        unitConfig.RequiresMountsFor = [ environmentFile ];
        wants = [ "docker-network-traefik.service" ];
        after = [ "docker-network-traefik.service" ];
        restartTriggers = [ settings ];
      };
      virtualisation.oci-containers.containers.searxng = {
        image = lib.mkDefault "searxng/searxng:2026.10.4-d48c4b555";
        environmentFiles = [ environmentFile ];
        environment = lib.mapAttrs (_: lib.mkDefault) {
          FORCE_OWNERSHIP = "false";
          SEARXNG_BASE_URL = "https://${s.hostname}/";
          SEARXNG_BIND_ADDRESS = "0.0.0.0";
          SEARXNG_LIMITER = "false";
          SEARXNG_PORT = "8080";
          SEARXNG_SETTINGS_PATH = "/etc/searxng/settings.yml";
        };
        autoRemoveOnStop = false;
        extraOptions = [
          "--restart=unless-stopped"
          "--network-alias=searxng"
          "--cap-drop=ALL"
          "--cap-add=CHOWN"
          "--cap-add=SETGID"
          "--cap-add=SETUID"
          "--cap-add=DAC_OVERRIDE"
          "--security-opt=no-new-privileges:true"
        ];
        volumes = [
          "${settings}:/etc/searxng/settings.yml:ro"
          "/etc/localtime:/etc/localtime:ro"
        ];
        networks = [ "traefik" ];
      };
    })
  ];
}
