{
  config,
  lib,
  pkgs,
  ...
}:
let
  ps = import ../public-services/lib.nix { inherit lib; };
  selected = ps.select config "groupware";
  cfg = selected.cfg;
  hostname = if selected.enabled then selected.hostname else "";
  dataDir = ps.require "groupware" "dataDir" cfg.dataDir;
  radicale = config.services.radicale;
  productName = lib.replaceStrings [ "\\" "'" ] [ "\\\\" "\\'" ] cfg.productName;
  carddavConfig = pkgs.writeText "roundcube-carddav-config.inc.php" ''
    <?php
    $prefs['Personal'] = [
      'accountname' => 'Personal',
      'username' => '%u',
      'password' => '%p',
      'discovery_url' => '${ps.url selected 80}/',
      'active' => true,
      'readonly' => false,
      'hide' => false,
      'fixed' => ['discovery_url', 'username', 'password', 'ssl_noverify', 'preemptive_basic_auth'],
    ];
  '';
  roundcubePackage = pkgs.buildEnv {
    name = "roundcube-with-carddav-config";
    paths = [
      (pkgs.roundcube.withPlugins (plugins: [ plugins.carddav ]))
      (pkgs.runCommand "roundcube-carddav-config-overlay" { } ''
        mkdir -p $out/plugins/carddav
        ln -s ${carddavConfig} $out/plugins/carddav/config.inc.php
      '')
    ];
  };
in
{
  config = lib.mkIf selected.enabled {
    services.roundcube = {
      enable = true;
      hostName = lib.mkDefault hostname;
      package = lib.mkDefault roundcubePackage;
      plugins = lib.mkDefault [ "carddav" ];
      extraConfig = lib.mkDefault ''
        $config['imap_host'] = 'ssl://${hostname}:993';
        $config['smtp_host'] = 'tls://${hostname}:587';
        $config['smtp_user'] = '%u';
        $config['smtp_pass'] = '%p';
        $config['product_name'] = '${productName}';
      '';
    };

    services.nginx.virtualHosts.${hostname} = {
      listen = lib.mkIf selected.standalone (
        lib.mkDefault [
          {
            addr = "127.0.0.1";
            port = 80;
          }
        ]
      );
      # Roundcube supplies mkDefault true; this stronger default still permits ordinary overrides.
      forceSSL = lib.mkOverride 900 false;
      enableACME = lib.mkOverride 900 false;
      locations."/.well-known/carddav".extraConfig = lib.mkDefault ''
        absolute_redirect off;
        return 301 /radicale/;
      '';
      locations."/.well-known/caldav".extraConfig = lib.mkDefault ''
        absolute_redirect off;
        return 301 /radicale/;
      '';
      locations."/radicale/" = {
        proxyPass = lib.mkDefault "http://127.0.0.1:5232/";
        extraConfig = lib.mkDefault ''
          proxy_set_header Host $host;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto ${
            if selected.standalone then "$scheme" else "$http_x_forwarded_proto"
          };
          proxy_set_header X-Script-Name /radicale;
          proxy_set_header Authorization $http_authorization;
        '';
      };
    };

    systemd.tmpfiles.rules = [
      "d ${builtins.toJSON dataDir} 0750 ${radicale.user} ${radicale.group} -"
      "d ${builtins.toJSON "${dataDir}/collections"} 0750 ${radicale.user} ${radicale.group} -"
    ];
    systemd.services.radicale.unitConfig.RequiresMountsFor = [ dataDir ];
    services.radicale = {
      enable = true;
      settings = {
        # The mailserver is on this host (asserted). Its public name may resolve to a gateway that
        # this host cannot reach, so authenticate against the local Dovecot over loopback, where
        # Dovecot allows plaintext login and credentials never leave the host.
        auth = {
          type = lib.mkDefault "imap";
          imap_host = lib.mkDefault "127.0.0.1:143";
          imap_security = lib.mkDefault "none";
          cache_logins = lib.mkDefault true;
        };
        storage.filesystem_folder = lib.mkDefault "${dataDir}/collections";
      };
      rights = lib.mkDefault {
        root = {
          user = ".+";
          collection = "";
          permissions = "R";
        };
        principal = {
          user = ".+";
          collection = "{user}";
          permissions = "RW";
        };
        calendars = {
          user = ".+";
          collection = "{user}/[^/]+";
          permissions = "rw";
        };
      };
    };
  };
}
