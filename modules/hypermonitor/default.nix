{
  config,
  lib,
  ps,
  ...
}:
let
  inherit (lib) mkOption types;
  s = ps.select config "hypermonitor";
  url = types.strMatching "https?://[^[:space:]]+";
  unitName = types.strMatching "[A-Za-z0-9@_.:-]+\\.service";
  name = types.strMatching "[A-Za-z0-9][A-Za-z0-9_.-]*";

  host = types.submodule {
    options = {
      name = mkOption {
        type = name;
        description = "Host name as the dashboard shows it; Prometheus series carry it as the `host` label.";
      };
      agent = mkOption {
        type = types.nullOr name;
        default = null;
        description = "Agent (key of `agents`) for the host's units and power operations; null uses the agent of the same name when it exists.";
      };
      optional = mkOption {
        type = types.bool;
        default = false;
        description = "A stopped host is shown as asleep instead of down (machines that are switched off on purpose).";
      };
      gpu = mkOption {
        type = types.bool;
        default = false;
        description = "Show the GPU metrics of the host.";
      };
      wol = mkOption {
        type = types.nullOr (
          types.submodule {
            options = {
              mac = mkOption {
                type = types.strMatching "([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}";
                description = "MAC address for the Wake-on-LAN magic packet.";
              };
              broadcast = mkOption {
                type = types.strMatching "[^[:space:]]+:[0-9]+";
                example = "192.168.0.255:9";
                description = "Broadcast address:port the dashboard host sends the packet to.";
              };
            };
          }
        );
        default = null;
        description = "Wake-on-LAN of the host from the dashboard host; null for none.";
      };
      suspendUnit = mkOption {
        type = types.nullOr unitName;
        default = null;
        example = "hypermonitor-suspend.service";
        description = "Unit the host's agent starts to suspend the host (`modules.hypermonitor-power` on that host provides `hypermonitor-suspend.service`). Needs `jobs`.";
      };
      poweroffUnit = mkOption {
        type = types.nullOr unitName;
        default = null;
        example = "hypermonitor-poweroff.service";
        description = "Unit the host's agent starts to power the host off (`modules.hypermonitor-power` provides `hypermonitor-poweroff.service`). Needs `jobs`.";
      };
      jobs = mkOption {
        type = types.nullOr url;
        default = null;
        example = "http://192.0.2.10:9180/attos-jobs.json";
        description = "URL of the host's attos-jobs status (`modules.hypermonitor-power.publishJobs`): suspend and poweroff are refused while it lists work or a local login, or cannot be read.";
      };
      flake = mkOption {
        type = types.nullOr (types.strMatching "[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+");
        default = null;
        example = "AttODao/server-nix";
        description = "owner/repo on the `forgejo` instance whose `main` the host's deployed configuration revision (from its report) is compared with.";
      };
      report = mkOption {
        type = types.nullOr url;
        default = null;
        description = "URL of the host's host-report JSON (reboot required, Incus guests, deployed revision); null for none.";
      };
    };
  };

  agent = types.submodule {
    options = {
      socket = mkOption {
        type = types.nullOr ps.absolutePath;
        default = null;
        description = "attos-deck-agent unix socket on the dashboard host itself.";
      };
      ssh = mkOption {
        type = types.nullOr (types.strMatching "[A-Za-z0-9_.-]+@[^[:space:]-][^[:space:]]*");
        default = null;
        example = "attos-deck@10.0.0.2";
        description = "user@address of the SSH account whose key is forced to `attos-deck-agent ssh` on another host. The dashboard's own key is generated in the state directory at first start and logged by the unit.";
      };
    };
  };

  placement = types.submodule {
    options = {
      host = mkOption {
        type = name;
        description = "Dashboard host the services of this registry owner are shown under.";
      };
      agent = mkOption {
        type = types.nullOr name;
        default = null;
        description = "Agent that serves their units; null uses `host`.";
      };
    };
  };

  tokenFile = ps.pathOption "Runtime token file passed with LoadCredential (never copied into the Nix store); null queries anonymously.";

  serviceOptions = ps.common "HyperMonitor dashboard (server and web UI)" // {
    package = mkOption {
      type = types.nullOr types.package;
      default = null;
      description = "HyperMonitor package (bin/hypermonitor and share/hypermonitor/ui); null uses attopkgs.hypermonitor.";
    };
    stateDirectory = mkOption {
      type = types.strMatching "[a-z][a-z0-9-]*";
      default = "hypermonitor";
      description = "Name of the state directory under /var/lib (SQLite database, SSH key, agent host keys).";
    };
    ingestListen = mkOption {
      type = types.nullOr (types.strMatching "[^[:space:]]+:[0-9]+");
      default = null;
      description = "address:port of the bridge-only listener (Hermes bridge); null for none.";
    };
    ingestPeers = mkOption {
      type = types.listOf (types.strMatching "[0-9a-fA-F.:]+");
      default = [ ];
      example = [ "10.0.0.13" ];
      description = "IP addresses of the bridges (modules.hypermonitor-bridge) that may call `ingestListen`; the server answers every other peer with 403.";
    };
    ingestInterface = mkOption {
      type = types.nullOr types.nonEmptyStr;
      default = null;
      example = "incusbr0";
      description = "Interface the bridges come in on: opens `ingestListen` in the nftables firewall for `ingestPeers` on it only; null opens nothing.";
    };
    briefRetentionDays = mkOption {
      type = types.nullOr types.ints.positive;
      default = null;
      description = "Days the ingested morning Briefs are kept; null keeps the server default (365).";
    };
    trustedProxies = mkOption {
      type = types.listOf types.nonEmptyStr;
      default = [
        "127.0.0.1"
        "::1"
      ];
      description = "Peers (plain IP addresses) whose X-Forwarded-For names the client; the same-host gateway by default.";
    };
    sessionIdleHours = mkOption {
      type = types.nullOr types.ints.positive;
      default = null;
      description = "Hours without a request after which a login session ends; null keeps the server default (168).";
    };
    sessionMaxDays = mkOption {
      type = types.nullOr types.ints.positive;
      default = null;
      description = "Days after login at which a session ends; null keeps the server default (30).";
    };
    hosts = mkOption {
      type = types.listOf host;
      default = [ ];
      description = "Hosts shown on the dashboard, in order.";
    };
    agents = mkOption {
      type = types.attrsOf agent;
      default = { };
      description = "attos-deck-agent endpoints by name; exactly one of socket or ssh each.";
    };
    placement = mkOption {
      type = types.attrsOf placement;
      default = { };
      example = {
        guest = {
          host = "gateway";
          agent = "guest";
        };
      };
      description = "Registry owners (modules.public-services `host`) that are not dashboard hosts themselves, such as a guest, keyed by the owner name. Other owners map to the host and agent of the same name.";
    };
    prometheusUrl = mkOption {
      type = types.nullOr url;
      default = null;
      description = "Prometheus base URL with node_exporter series labelled `host`; null leaves host metrics unconfigured.";
    };
    forgejo = mkOption {
      type = types.nullOr (
        types.submodule {
          options = {
            url = mkOption {
              type = url;
              description = "Forgejo base URL.";
            };
            user = mkOption {
              type = types.nonEmptyStr;
              description = "User whose contributions, review requests and notifications are counted.";
            };
            owners = mkOption {
              type = types.listOf types.nonEmptyStr;
              default = [ ];
              description = "Users or organisations whose repositories are listed.";
            };
            inherit tokenFile;
          };
        }
      );
      default = null;
      description = "Forgejo source; null leaves it unconfigured.";
    };
    github = mkOption {
      type = types.nullOr (
        types.submodule {
          options = {
            user = mkOption {
              type = types.nonEmptyStr;
              description = "GitHub user or organisation.";
            };
            publicOnly = mkOption {
              type = types.bool;
              default = true;
              description = "Only public repositories (results, notifications and CI of private ones are dropped).";
            };
            inherit tokenFile;
          };
        }
      );
      default = null;
      description = "GitHub source; null leaves it unconfigured.";
    };
    ahd = mkOption {
      type = types.nullOr (
        types.submodule {
          options = {
            url = mkOption {
              type = url;
              description = "AttOsHoYoDashboard base URL.";
            };
            tokenFile = ps.pathOption "Runtime file with an AHD API token (scope run), passed with LoadCredential; null shows only the unauthenticated health.";
          };
        }
      );
      default = null;
      description = "AHD source; null leaves it unconfigured.";
    };
    hermes = mkOption {
      type = types.nullOr (
        types.submodule {
          options.url = mkOption {
            type = url;
            description = "Hermes dashboard base URL (GET /api/status without authentication).";
          };
        }
      );
      default = null;
      description = "Hermes source; null leaves it unconfigured.";
    };
  };
in
{
  imports = [
    ./nixos.nix
    ./catalog.nix
  ];

  options.modules = ps.moduleOptions "hypermonitor" serviceOptions // {
    hypermonitor-settings = mkOption {
      type = types.attrs;
      default = { };
      internal = true;
      description = "The generated config.toml as an attribute set (read by the evaluation tests).";
    };
  };

  config.assertions =
    s.assertions
    ++ lib.optionals s.enabled (
      lib.mapAttrsToList (agentName: a: {
        assertion = (a.socket == null) != (a.ssh == null);
        message = "hypermonitor.agents.${agentName}: set exactly one of socket and ssh.";
      }) s.cfg.agents
      ++ [
        {
          assertion = s.cfg.ingestListen == null || s.cfg.ingestPeers != [ ];
          message = "hypermonitor.ingestListen needs ingestPeers (the bridges allowed to call it).";
        }
        {
          assertion = s.cfg.ingestInterface == null || config.networking.nftables.enable;
          message = "hypermonitor.ingestInterface opens the port with nftables rules: enable networking.nftables.";
        }
      ]
    );
}
