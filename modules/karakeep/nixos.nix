{
  config,
  lib,
  pkgs,
  attopkgs,
  ps,
  ...
}:
let
  s = ps.select config "karakeep";
  cfg = s.cfg;
  dataDir = ps.require "karakeep" "dataDir" cfg.dataDir;
  environmentFile = ps.require "karakeep" "environmentFile" cfg.environmentFile;
  listen = ps.listen s 3001;
  baseUrl = ps.url s 3001;
  stateDir = "/var/lib/karakeep";
  meiliKey = "/run/karakeep-meilisearch/master-key";
  units = [
    "karakeep-init"
    "karakeep-workers"
    "karakeep-web"
  ];
in
{
  config = lib.mkIf s.enabled {
    services.karakeep = {
      enable = true;
      inherit environmentFile;
      browser.exe = toString (
        pkgs.writeShellScript "karakeep-chromium" ''
          exec ${lib.getExe pkgs.chromium} --disable-blink-features=AutomationControlled --window-size=1440,900 "$@"
        ''
      );
      extraEnvironment = lib.mapAttrs (_: lib.mkDefault) (
        {
          HOSTNAME = listen.address;
          PORT = toString listen.port;
          NEXTAUTH_URL = baseUrl;
          LOG_LEVEL = "notice";
          DB_WAL_MODE = "true";
          RATE_LIMITING_ENABLED = "true";
          CRAWLER_FULL_PAGE_ARCHIVE = "true";
          CRAWLER_MONOLITH_TIMEOUT_SEC = "300";
          CRAWLER_JOB_TIMEOUT_SEC = "900";
          MONOLITH_FRAGMENT_NAVIGATION_PREFIX = "${baseUrl}/api/assets/";
        }
        // cfg.environment
      );
    };
    services.meilisearch.masterKeyFile = meiliKey;
    fonts.packages = [ pkgs.noto-fonts-cjk-sans ];

    systemd.tmpfiles.settings."10-karakeep" = {
      ${dataDir}.d = {
        mode = lib.mkDefault "0755";
        user = lib.mkDefault "root";
        group = lib.mkDefault "root";
      };
      "${dataDir}/data" = {
        d = {
          mode = lib.mkDefault "0750";
          user = lib.mkDefault "karakeep";
          group = lib.mkDefault "karakeep";
        };
        Z = {
          user = lib.mkDefault "karakeep";
          group = lib.mkDefault "karakeep";
        };
      };
    };

    systemd.services = lib.mkMerge [
      (lib.genAttrs units (_: {
        unitConfig.RequiresMountsFor = [ dataDir ];
        serviceConfig.BindPaths = [ "${dataDir}/data:${stateDir}" ];
      }))
      {
        karakeep-web = { inherit (ps.afterNetworkOnline) wants after; };
        karakeep-workers.path = lib.mkBefore [ attopkgs.karakeep-monolith ];
        karakeep-meilisearch-key = {
          before = [ "meilisearch.service" ];
          requiredBy = [ "meilisearch.service" ];
          unitConfig.RequiresMountsFor = [ environmentFile ];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            RuntimeDirectory = "karakeep-meilisearch";
            RuntimeDirectoryMode = "0700";
            UMask = "0077";
          };
          script = ''
            value=
            while IFS= read -r line || [ -n "$line" ]; do
              line="''${line#export }"
              case "$line" in
                MEILI_MASTER_KEY=*) value="''${line#MEILI_MASTER_KEY=}" ;;
              esac
            done < ${lib.escapeShellArg environmentFile}
            case "$value" in
              \"*\") value="''${value#\"}"; value="''${value%\"}" ;;
              \'*\') value="''${value#\'}"; value="''${value%\'}" ;;
            esac
            if [ -z "$value" ]; then
              echo "Karakeep environmentFile must define a nonempty MEILI_MASTER_KEY" >&2
              exit 1
            fi
            printf %s "$value" > ${meiliKey}
          '';
        };
      }
    ];
    networking.firewall = ps.backendFirewall config s [ ];
  };
}
