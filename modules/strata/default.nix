{
  config,
  lib,
  ps,
  ...
}:
let
  s = ps.select config "strata";
in
{
  imports = [
    ./nixos.nix
    ./gateway.nix
  ];

  options.modules = ps.moduleOptions "strata" (
    ps.common "Strata on-demand AMD LLM API"
    // {
      flavor = lib.mkOption {
        type = lib.types.nullOr (
          lib.types.enum [
            "rocm-gfx110x"
            "rocm-gfx120x"
            "rocm-gfx1151"
          ]
        );
        default = null;
        description = "AMD image flavor matching the GPU; required for local deployment.";
      };
      dataDir = ps.pathOption "Persistent /data volume (models, prepared packs, tuning and state).";
      models = lib.mkOption {
        type = lib.types.addCheck (lib.types.listOf (lib.types.strMatching "[A-Za-z0-9][A-Za-z0-9_.-]*")) (
          xs: xs != [ ]
        );
        default = [ "IQ3_S" ];
        example = [
          "IQ3_S"
          "IQ3_XXS"
          "Q2_0"
        ];
        description = "MODEL identifiers offered by the session; the first starts after ten seconds.";
      };
      context = lib.mkOption {
        type = lib.types.nullOr lib.types.nonEmptyStr;
        default = null;
        description = "CONTEXT passed to Strata, such as 32k; null lets Strata choose.";
      };
      apiKeyFile = ps.pathOption "Runtime root:root 0400 file containing only the API key; required locally.";
      user = lib.mkOption {
        type = lib.types.nullOr lib.types.nonEmptyStr;
        default = null;
        description = "Consumer-owned account running the greeter session and permitted to start/stop model units.";
      };
      wake = {
        enable = lib.mkEnableOption "on-demand start: the gateway wakes the owner (Wake-on-LAN), starts Strata for POST requests and stops what it started after idleness";
        controlUrl = lib.mkOption {
          type = lib.types.nullOr lib.types.nonEmptyStr;
          default = null;
          example = "http://192.168.0.99:8091";
          description = "http://address:port of the owner's control API; the owner binds it and the gateway calls it. Required when wake is enabled. The consumer restricts the port to the gateway in its firewall.";
        };
        gatewayListen = lib.mkOption {
          type = lib.types.nonEmptyStr;
          default = "127.0.0.1:8090";
          description = "address:port of the gateway-side proxy that Traefik routes to instead of backendUrl.";
        };
        macAddress = lib.mkOption {
          type = lib.types.nullOr (lib.types.strMatching "([0-9a-f]{2}:){5}[0-9a-f]{2}");
          default = null;
          description = "Owner NIC MAC for Wake-on-LAN; null disables waking.";
        };
        broadcast = lib.mkOption {
          type = lib.types.nonEmptyStr;
          default = "255.255.255.255:9";
          description = "Broadcast address:port for the magic packet.";
        };
        powerOff = lib.mkEnableOption "powering the owner off after an idle stop when the gateway had woken it with Wake-on-LAN; the owner refuses while a local login exists (then stays on), and postpones while an SSH session, a Docker container (CI job) or a heavy job runs";
        idleMinutes = lib.mkOption {
          type = lib.types.ints.positive;
          default = 30;
          description = "Stop a Strata unit that the gateway started after this many minutes without requests.";
        };
      };
    }
  );

  config = lib.mkMerge [
    { assertions = s.assertions; }
    {
      assertions = [
        {
          assertion = !(config.modules.strata.wake.enable or false);
          message = "strata: wake requires the public-services registry (modules.public-services.<FQDN>.strata).";
        }
      ]
      ++ map (entry: {
        assertion =
          !entry.cfg.wake.enable
          || (
            entry.cfg.wake.controlUrl != null
            && builtins.match "http://[^/:]+:[0-9]+/?" entry.cfg.wake.controlUrl != null
          );
        message = "modules.public-services.${entry.hostname}.strata.wake.controlUrl must be http://<address>:<port> when wake is enabled.";
      }) (ps.entries config "strata");
    }
    (lib.mkIf s.enabled { modules.docker.enable = true; })
  ];
}
