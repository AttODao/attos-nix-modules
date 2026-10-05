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
  mailHost = if cfg.mailserverHostName == null then hostname else cfg.mailserverHostName;
  dataDir = ps.require "groupware" "dataDir" cfg.dataDir;
  radicale = config.services.radicale;
  accounts = lib.filterAttrs (_: account: !(account.sendOnly or false)) config.mailserver.accounts;
  hashFiles = lib.mapAttrsToList (_: account: account.hashedPasswordFile) accounts;
  accountArgs = lib.concatLists (
    lib.mapAttrsToList (name: account: [
      name
      account.hashedPasswordFile
    ]) accounts
  );
  runtimeUsers = pkgs.writeShellScript "radicale-users" ''
    exec ${pkgs.python3}/bin/python3 ${./radicale-users.py} ${
      lib.escapeShellArgs (
        [
          "${dataDir}/secrets/users"
          radicale.group
        ]
        ++ accountArgs
      )
    }
  '';
  carddavConfig = pkgs.writeText "roundcube-carddav-config.inc.php" ''
    <?php
    $prefs['Personal'] = [
      'accountname' => 'Personal',
      'username' => '%u',
      'password' => '%p',
      'discovery_url' => 'https://${hostname}/',
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
    assertions = [
      {
        assertion = lib.all (path: path != null && ps.absolutePath.check path) hashFiles;
        message = "groupware: every receiving mailserver.accounts entry needs an absolute runtime hashedPasswordFile containing a bcrypt hash.";
      }
    ];

    services.roundcube = {
      enable = true;
      hostName = lib.mkDefault hostname;
      package = lib.mkDefault roundcubePackage;
      plugins = lib.mkDefault [ "carddav" ];
      extraConfig = lib.mkDefault ''
        $config['imap_host'] = 'ssl://${mailHost}:993';
        $config['smtp_host'] = 'tls://${mailHost}:587';
        $config['smtp_user'] = '%u';
        $config['smtp_pass'] = '%p';
        $config['product_name'] = 'Mail';
      '';
    };

    services.nginx.virtualHosts.${hostname} = {
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
          proxy_set_header X-Forwarded-Proto $http_x_forwarded_proto;
          proxy_set_header X-Script-Name /radicale;
          proxy_set_header Authorization $http_authorization;
        '';
      };
    };

    systemd.tmpfiles.rules = [
      "d ${builtins.toJSON dataDir} 0750 ${radicale.user} ${radicale.group} -"
      "d ${builtins.toJSON "${dataDir}/collections"} 0750 ${radicale.user} ${radicale.group} -"
      "d ${builtins.toJSON "${dataDir}/secrets"} 0750 root ${radicale.group} -"
    ];
    systemd.services.radicale-users = {
      description = "Generate Radicale users from runtime mail password hashes";
      requiredBy = [ "radicale.service" ];
      before = [ "radicale.service" ];
      restartTriggers = [ runtimeUsers ];
      unitConfig.RequiresMountsFor = [ dataDir ] ++ hashFiles;
      serviceConfig.Type = "oneshot";
      script = "exec ${runtimeUsers}";
    };
    systemd.services.radicale = {
      requires = [ "radicale-users.service" ];
      after = [ "radicale-users.service" ];
      restartTriggers = [ runtimeUsers ];
      unitConfig.RequiresMountsFor = [ dataDir ];
    };
    services.radicale = {
      enable = true;
      settings = {
        auth = {
          type = lib.mkDefault "htpasswd";
          htpasswd_filename = lib.mkDefault "${dataDir}/secrets/users";
          htpasswd_encryption = lib.mkDefault "bcrypt";
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
