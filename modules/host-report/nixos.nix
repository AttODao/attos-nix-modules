{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.modules.host-report;
  collector = pkgs.writers.writePython3Bin "host-report" { } (builtins.readFile ./host-report.py);
  settings = pkgs.writeText "host-report.json" (
    builtins.toJSON {
      host = config.networking.hostName;
      inherit (cfg)
        readerGroup
        publish
        fetch
        alert
        logChecks
        ;
      docker = config.virtualisation.docker.enable;
      incus = config.virtualisation.incus.enable;
      nftables = config.networking.nftables.enable;
    }
  );
  check =
    units: pattern: ipPattern: failure:
    lib.mapAttrs (_: lib.mkDefault) {
      inherit
        units
        pattern
        ipPattern
        failure
        ;
    };
in
{
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !cfg.publish.enable || cfg.publish.address != null;
        message = "host-report: publish.address is required.";
      }
      {
        assertion = !cfg.alert.enable || cfg.alert.to != null;
        message = "host-report: alert.to is required.";
      }
      {
        assertion = lib.all (
          name: builtins.match "[a-zA-Z0-9][a-zA-Z0-9_.-]*" name != null && name != config.networking.hostName
        ) (builtins.attrNames cfg.fetch);
        message = "host-report: fetch keys must be safe peer host names distinct from this host.";
      }
      {
        assertion = lib.hasPrefix "/" cfg.alert.sendmail;
        message = "host-report: alert.sendmail must be absolute.";
      }
    ];
    modules.host-report.logChecks =
      lib.optionalAttrs config.services.openssh.enable {
        sshd = check [
          "sshd.service"
        ] "Failed password|Invalid user|authentication failure" "(?:from |rhost=)([0-9a-fA-F:.]+)" true;
        sshAccepted = check [
          "sshd.service"
        ] "Accepted \\S+ for (?P<user>\\S+) from " "from ([0-9a-fA-F:.]+)" false;
      }
      // lib.optionalAttrs config.security.sudo.enable {
        sudo = check [ ] "(?P<user>\\S+)\\s*:.*COMMAND=(?P<command>\\S+)" null false;
      }
      // lib.optionalAttrs config.services.fail2ban.enable {
        fail2ban = check [
          "fail2ban.service"
        ] "(?P<action>Ban|Unban) " "(?:Ban|Unban) ([0-9a-fA-F:.]+)" false;
      }
      // lib.optionalAttrs config.services.dovecot2.enable {
        dovecot = check [
          "dovecot2.service"
          "dovecot.service"
        ] "auth failed|Authentication failure" "rip=([0-9a-fA-F:.]+)" true;
      }
      // lib.optionalAttrs config.services.postfix.enable {
        postfix = check [ "postfix.service" ] "SASL .*authentication failed" "\\[([0-9a-fA-F:.]+)\\]" true;
      }
      // lib.optionalAttrs config.services.forgejo.enable {
        forgejo = check [
          "forgejo.service"
        ] "Failed authentication attempt" "from (?:\\[)?([0-9a-fA-F:.]+)" true;
      }
      // lib.optionalAttrs config.services.vaultwarden.enable {
        vaultwarden = check [
          "vaultwarden.service"
        ] "Username or password is incorrect" "IP: ([0-9a-fA-F:.]+)" true;
      };
    systemd.tmpfiles.rules = [
      "d /var/lib/host-report 0750 root ${if cfg.readerGroup == null then "root" else cfg.readerGroup} -"
      "d /var/lib/host-report/private 0700 root root -"
    ]
    ++ lib.optionals cfg.publish.enable [ "d /var/lib/host-report-publish 0755 root root -" ];
    systemd.services.host-report = {
      description = "Collect host health and security summaries";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      path = [
        pkgs.systemd
        pkgs.util-linux
        pkgs.btrfs-progs
        pkgs.smartmontools
        pkgs.wireguard-tools
      ]
      ++ lib.optional config.virtualisation.docker.enable pkgs.docker
      ++ lib.optional config.virtualisation.incus.enable config.virtualisation.incus.package
      ++ lib.optional config.networking.nftables.enable pkgs.nftables;
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Group = if cfg.readerGroup == null then "root" else cfg.readerGroup;
        ExecStart = "${collector}/bin/host-report ${settings}";
        StateDirectory = "host-report";
        StateDirectoryMode = "0750";
        UMask = "0077";
        Nice = 19;
        IOSchedulingClass = "idle";
        TimeoutStartSec = "10min";
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        PrivateTmp = true;
        NoNewPrivileges = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        ReadWritePaths =
          lib.optional cfg.publish.enable "/var/lib/host-report-publish"
          ++ lib.optionals cfg.alert.enable [
            "-/var/lib/postfix/queue"
            "-/var/spool/postfix"
          ];
      };
    };
    systemd.timers.host-report = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.onCalendar;
        Persistent = true;
        RandomizedDelaySec = "30s";
      };
    };
    systemd.services.host-report-publish = lib.mkIf cfg.publish.enable {
      description = "Publish only the local host report";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [
        "network-online.target"
        "systemd-tmpfiles-setup.service"
      ];
      serviceConfig = {
        ExecStart = "${pkgs.darkhttpd}/bin/darkhttpd /var/lib/host-report-publish --addr ${lib.escapeShellArg cfg.publish.address} --port ${toString cfg.publish.port} --no-listing --no-server-id";
        DynamicUser = true;
        Restart = "on-failure";
        RestartSec = "10s";
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        PrivateDevices = true;
        NoNewPrivileges = true;
        CapabilityBoundingSet = "";
        InaccessiblePaths = [ "/var/lib/host-report" ];
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
        ];
      };
    };
  };
}
