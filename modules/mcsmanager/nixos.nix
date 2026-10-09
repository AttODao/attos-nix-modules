{
  config,
  lib,
  pkgs,
  attopkgs,
  ...
}:
let
  ps = import ../public-services/lib.nix { inherit lib; };
  s = ps.select config "mcsmanager";
  cfg = s.cfg;
  required = field: ps.require "mcsmanager" field cfg.${field};
  root = required "dataDir";
  keyFile = if cfg.generateDaemonKey then "${root}/daemon-key" else required "daemonKeyFile";
  webUser = required "webUser";
  daemonUser = required "daemonUser";
  group = required "group";
  listenAddress = if s.standalone then "127.0.0.1" else cfg.listenAddress;
  packageDir = "${attopkgs.mcsmanager}/share/mcsmanager";
  settings = pkgs.writeText "mcsmanager-runtime-settings.json" (
    builtins.toJSON {
      dataDir = root;
      inherit packageDir listenAddress;
      inherit (s) hostname standalone;
      inherit (cfg) webPort daemonPort;
      initialAdmin = cfg.initialAdminFile != null;
    }
  );
  nonRoot =
    user:
    user != "root"
    && builtins.hasAttr user config.users.users
    && config.users.users.${user}.uid != 0
    && config.users.users.${user}.group != "docker"
    && !lib.elem "docker" config.users.users.${user}.extraGroups;
  # ponytail: native games share the daemon UID; use per-game VMs for mutually untrusted tenants.
  service = kind: user: {
    description = "MCSManager native ${kind}";
    wantedBy = [ "multi-user.target" ];
    after = [
      "network.target"
    ]
    ++ lib.optional cfg.generateDaemonKey "mcsmanager-key.service"
    ++ lib.optional (kind == "web") "mcsmanager-daemon.service";
    requires = lib.optional cfg.generateDaemonKey "mcsmanager-key.service";
    wants = lib.optional (kind == "web") "mcsmanager-daemon.service";
    unitConfig.RequiresMountsFor = [
      root
      keyFile
    ]
    ++ lib.optional (kind == "web" && cfg.initialAdminFile != null) cfg.initialAdminFile;
    path = lib.mkDefault (
      [
        pkgs.bash
        pkgs.coreutils
        pkgs.procps
        pkgs.gnutar
        pkgs.unzip
      ]
      ++ lib.optional (kind == "daemon") pkgs.jre_headless
    );
    serviceConfig = {
      Type = lib.mkDefault "simple";
      User = lib.mkDefault user;
      Group = lib.mkDefault group;
      WorkingDirectory = lib.mkDefault "${root}/${kind}";
      ExecStartPre = lib.mkDefault "${pkgs.nodejs}/bin/node ${./bootstrap.cjs} ${kind} ${settings}";
      ExecStart = lib.mkDefault "${pkgs.nodejs}/bin/node ${packageDir}/${kind}/app.js";
      LoadCredential = lib.mkDefault (
        [ "daemon-key:${keyFile}" ]
        ++ lib.optional (
          kind == "web" && cfg.initialAdminFile != null
        ) "initial-admin:${cfg.initialAdminFile}"
      );
      Restart = lib.mkDefault "on-failure";
      RestartSec = lib.mkDefault 5;
      TimeoutStopSec = lib.mkDefault "90s";
      UMask = lib.mkDefault "0077";
      NoNewPrivileges = lib.mkDefault true;
      ProtectSystem = lib.mkDefault "strict";
      ProtectHome = lib.mkDefault true;
      PrivateTmp = lib.mkDefault true;
      PrivateDevices = lib.mkDefault true;
      ProtectKernelTunables = lib.mkDefault true;
      ProtectKernelModules = lib.mkDefault true;
      ProtectKernelLogs = lib.mkDefault true;
      ProtectControlGroups = lib.mkDefault true;
      RestrictSUIDSGID = lib.mkDefault true;
      LockPersonality = lib.mkDefault true;
      CapabilityBoundingSet = lib.mkDefault [ ];
      RestrictAddressFamilies = lib.mkDefault [
        "AF_UNIX"
        "AF_INET"
        "AF_INET6"
      ];
      ReadWritePaths = lib.mkDefault [ "${root}/${kind}" ];
      InaccessiblePaths = [
        "-/run/docker.sock"
        "-/var/run/docker.sock"
      ];
    };
  };
in
{
  config = lib.mkMerge [
    { assertions = s.assertions; }
    (lib.mkIf s.enabled {
      assertions = [
        {
          assertion = !cfg.generateDaemonKey || cfg.daemonKeyFile == null || cfg.daemonKeyFile == keyFile;
          message = "mcsmanager: generated daemon keys live at dataDir/daemon-key; daemonKeyFile must be null or match that path.";
        }
        {
          assertion = nonRoot webUser && nonRoot daemonUser && webUser != daemonUser;
          message = "mcsmanager: declare separate existing non-root webUser and daemonUser accounts without Docker group membership.";
        }
        {
          assertion =
            group != "root"
            && group != "docker"
            && builtins.hasAttr group config.users.groups
            && config.users.groups.${group}.gid != 0;
          message = "mcsmanager: declare an existing non-root, non-Docker group.";
        }
        {
          assertion = cfg.webPort != cfg.daemonPort;
          message = "mcsmanager: webPort and daemonPort must differ.";
        }
        {
          assertion =
            !lib.elem cfg.webPort (cfg.tcpPorts ++ cfg.udpPorts)
            && !lib.elem cfg.daemonPort (cfg.tcpPorts ++ cfg.udpPorts);
          message = "mcsmanager: management listener ports cannot be published as game ports.";
        }
        {
          assertion =
            nonRoot config.systemd.services.mcsmanager-web.serviceConfig.User
            && nonRoot config.systemd.services.mcsmanager-daemon.serviceConfig.User
            &&
              config.systemd.services.mcsmanager-web.serviceConfig.User
              != config.systemd.services.mcsmanager-daemon.serviceConfig.User;
          message = "mcsmanager: systemd service users must remain separate non-root accounts without Docker access.";
        }
        {
          assertion =
            lib.all
              (
                actualGroup:
                actualGroup != "root"
                && actualGroup != "docker"
                && builtins.hasAttr actualGroup config.users.groups
                && config.users.groups.${actualGroup}.gid != 0
              )
              [
                config.systemd.services.mcsmanager-web.serviceConfig.Group
                config.systemd.services.mcsmanager-daemon.serviceConfig.Group
              ];
          message = "mcsmanager: effective systemd groups must remain non-root and non-Docker.";
        }
        {
          assertion = root != "/";
          message = "mcsmanager: dataDir must be a dedicated service directory, not the filesystem root.";
        }
      ];
      systemd.tmpfiles.rules = [
        "d ${builtins.toJSON root} 0711 root root -"
        "d ${builtins.toJSON "${root}/web"} 0700 ${webUser} ${group} -"
        "d ${builtins.toJSON "${root}/daemon"} 0700 ${daemonUser} ${group} -"
      ];
      systemd.services.mcsmanager-key = lib.mkIf cfg.generateDaemonKey {
        description = "Create the native MCSManager daemon credential once";
        after = [ "systemd-tmpfiles-setup.service" ];
        requires = [ "systemd-tmpfiles-setup.service" ];
        unitConfig = {
          ConditionPathExists = "!${keyFile}";
          RequiresMountsFor = [ root ];
        };
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          UMask = "0077";
        };
        script = ''
          keyTmp=$(${pkgs.coreutils}/bin/mktemp ${lib.escapeShellArg "${root}/.daemon-key.XXXXXX"})
          trap '${pkgs.coreutils}/bin/rm -f "$keyTmp"' EXIT
          ${pkgs.openssl}/bin/openssl rand -hex 32 > "$keyTmp"
          ${pkgs.coreutils}/bin/mv -T "$keyTmp" ${lib.escapeShellArg keyFile}
        '';
      };
      systemd.services.mcsmanager-web = service "web" webUser;
      systemd.services.mcsmanager-daemon = service "daemon" daemonUser;
    })
  ];
}
