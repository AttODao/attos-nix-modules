{
  config,
  lib,
  pkgs,
  ps,
  attopkgs,
  ...
}:
let
  s = ps.select config "strata";
in
{
  config = lib.mkIf s.enabled (
    let
      cfg = s.cfg;
      wake = cfg.wake.enable;
      controlEndpoint = builtins.match "http://([^/:]+):([0-9]+)/?" (
        ps.require "strata" "wake.controlUrl" cfg.wake.controlUrl
      );
      controlConfig = pkgs.writeText "strata-wake-control.json" (
        builtins.toJSON {
          listen = "${builtins.head controlEndpoint}:${builtins.elemAt controlEndpoint 1}";
          units = map (model: {
            inherit model;
            unit = "${name model}.service";
          }) cfg.models;
          inherit healthUrl;
          systemctl = "${pkgs.systemd}/bin/systemctl";
          loginctl = "${pkgs.systemd}/bin/loginctl";
          # Checked before a power-off: a running Docker container or heavy job postpones it.
          cgroupRoot = "/sys/fs/cgroup";
          heavyLock = lib.optionalString (config.modules.heavy.enable or false) "/run/heavy/lock";
        }
      );
      user = ps.require "strata" "user" cfg.user;
      group = config.users.users.${user}.group;
      root = ps.require "strata" "dataDir" cfg.dataDir;
      keyFile = ps.require "strata" "apiKeyFile" cfg.apiKeyFile;
      flavor = ps.require "strata" "flavor" cfg.flavor;
      images = {
        rocm-gfx110x = "ghcr.io/niko1221/strata:0.2.13-rocm-gfx110x@sha256:a68f6ac1d013436115f025b6b6b95f30d9917a61d6ec418ff0517a49880d43e6";
        rocm-gfx120x = "ghcr.io/niko1221/strata:0.2.13-rocm-gfx120x@sha256:c68ebd4ecbf73f7f450bea4a60bbc014be83d78c9fbfbdc16df6f553cb442235";
        rocm-gfx1151 = "ghcr.io/niko1221/strata:0.2.13-rocm-gfx1151@sha256:3c96aa87d636230d2c8e804f60f93f6b630e9eb0c137cf722de1482d1fb8f92f";
      };
      name = model: "strata-headless-${lib.toLower (lib.replaceStrings [ "_" "." ] [ "-" "-" ] model)}";
      names = map name cfg.models;
      units = map (n: "${n}.service") names;
      endpoint = ps.listen s 8080;
      healthAddress =
        if lib.hasInfix ":" endpoint.address then "[${endpoint.address}]" else endpoint.address;
      healthUrl = "http://${healthAddress}:${toString endpoint.port}/health";
      sessionPackage = attopkgs.strata-headless-session {
        sessionConfig = {
          systemctl = "${pkgs.systemd}/bin/systemctl";
          setterm = "${pkgs.util-linux}/bin/setterm";
          endpoint = ps.url s 8080;
          inherit healthUrl;
          models = map (model: {
            inherit model;
            unit = "${name model}.service";
            log = "/run/${name model}/console.log";
          }) cfg.models;
        };
      };
      docker = "${pkgs.docker}/bin/docker";
      # Host GIDs: a group name given to --group-add resolves in the image's /etc/group instead.
      gid = pkgs.writeShellScript "strata-host-gid" ''
        ${pkgs.getent}/bin/getent group "$1" | ${pkgs.coreutils}/bin/cut -d: -f3 | ${pkgs.gnugrep}/bin/grep .
      '';
      q = lib.escapeShellArg;
      services = lib.imap0 (
        index: model:
        let
          n = name model;
          runtime = "/run/${n}";
          prepare = pkgs.writeShellScript "${n}-prepare" ''
            set -euo pipefail
            ${docker} rm -f strata-headless >/dev/null 2>&1 || true
            # Hand over files an older root container wrote before running as the configured user.
            ${pkgs.findutils}/bin/find ${q root} -xdev \( ! -user ${q user} -o ! -group ${q group} \) \
              -exec ${pkgs.coreutils}/bin/chown -h ${q "${user}:${group}"} {} +
            ${sessionPackage.python}/bin/python ${sessionPackage}/libexec/prepare.py ${q keyFile} ${q runtime} "$(${pkgs.coreutils}/bin/id -g ${q user})"
          '';
          run = pkgs.writeShellScript "${n}-run" ''
            set -euo pipefail
            exec > >(${pkgs.coreutils}/bin/tee -a ${q "${runtime}/console.log"}) 2>&1
            # Upstream HEALTHCHECK passes its key in argv; use unauthenticated /health in the session instead.
            # Run without root privileges, with user-owned persistent data.
            exec ${docker} run --rm --name strata-headless --no-healthcheck \
              --user "$(${pkgs.coreutils}/bin/id -u ${q user}):$(${pkgs.coreutils}/bin/id -g ${q user})" \
              --device /dev/kfd --device /dev/dri \
              --group-add "$(${gid} video)" --group-add "$(${gid} render)" \
              --ulimit memlock=-1:-1 --shm-size 2g --stop-timeout 120 \
              --env-file ${q "${runtime}/secret/environment"} \
              --env ${q "MODEL=${model}"} --env ${q "PRESET=headless-${lib.toLower model}"} --env PORT=8080 \
              ${lib.optionalString (cfg.context != null) "--env ${q "CONTEXT=${cfg.context}"} "}\
              ${lib.concatMapStringsSep " " (port: "--publish ${q port}") (ps.publish s 8080 8080)} \
              --volume ${q "${root}:/data"} ${q images.${flavor}}
          '';
          stop = pkgs.writeShellScript "${n}-stop" ''
            ${docker} stop -t 120 strata-headless >/dev/null 2>&1 || true
          '';
        in
        lib.nameValuePair n (
          lib.mkMerge [
            ps.afterNetworkOnline
            {
              description = "Strata API (${model}), on demand";
              # Ordering every pair makes Conflicts wait for the old container to release VRAM.
              after = [ "docker.service" ] ++ lib.take index units;
              wants = [ "docker.service" ];
              conflicts = lib.filter (unit: unit != "${n}.service") units;
              unitConfig.RequiresMountsFor = lib.mkDefault [ root ];
              serviceConfig = {
                Type = "simple";
                ExecStartPre = [ prepare ];
                ExecStart = run;
                ExecStop = stop;
                TimeoutStopSec = lib.mkDefault 150;
                Restart = lib.mkDefault "no";
                RuntimeDirectory = n;
                RuntimeDirectoryMode = "0750";
                RuntimeDirectoryPreserve = "yes";
                Group = group;
                UMask = "0077";
                StandardOutput = "journal";
                StandardError = "journal";
              };
            }
          ]
        )
      ) cfg.models;
    in
    {
      # attos-jobs lists a running model (often started by the gateway's wake) as stoppable remote work.
      modules.attos-jobs.units = units;
      assertions = [
        {
          assertion = builtins.length names == builtins.length (lib.unique names);
          message = "strata: models must have unique sanitized lowercase unit names.";
        }
        {
          assertion = config.users.users ? ${user};
          message = "strata: user must be an existing consumer-owned account.";
        }
        {
          assertion = pkgs.stdenv.hostPlatform.system == "x86_64-linux";
          message = "strata: official GPU images support x86_64-linux only.";
        }
      ];
      systemd.services =
        lib.listToAttrs services
        // lib.optionalAttrs wake {
          # The gateway's strata-wake gate calls this API to start/stop the units and to see
          # whether the desktop is in use; firewalling the port to the gateway is the consumer's.
          strata-wake-control = lib.mkMerge [
            ps.afterNetworkOnline
            {
              description = "Strata on-demand control API";
              wantedBy = [ "multi-user.target" ];
              serviceConfig = {
                User = "strata-control";
                Group = "strata-control";
                ExecStart = "${lib.getExe attopkgs.strata-wake} control --config ${controlConfig}";
                Restart = "on-failure";
                RestartSec = 5;
                NoNewPrivileges = true;
                ProtectSystem = "strict";
                ProtectHome = true;
                PrivateTmp = true;
              };
            }
          ];
        };
      users.users.strata-control = lib.mkIf wake {
        isSystemUser = true;
        group = "strata-control";
      };
      users.groups.strata-control = lib.mkIf wake { };
      systemd.tmpfiles.settings."10-strata".${root}.d = {
        mode = lib.mkDefault "0750";
        user = lib.mkDefault user;
        group = lib.mkDefault group;
      };
      environment.systemPackages = [ sessionPackage ];
      services.displayManager.sessionPackages = [ sessionPackage ];
      security.polkit.enable = lib.mkDefault true;
      security.polkit.extraConfig = ''
        polkit.addRule(function(action, subject) {
          var units = ${builtins.toJSON units};
          if (action.id === "org.freedesktop.systemd1.manage-units" &&
              subject.user === ${builtins.toJSON user} &&
              units.indexOf(action.lookup("unit")) !== -1) {
            var verb = action.lookup("verb");
            if (verb === "stop" || (verb === "start" && subject.local && subject.active)) {
              return polkit.Result.YES;
            }
          }
        });
      ''
      + lib.optionalString wake ''
        // strata-wake-control (the gateway's on-demand start) may start/stop the same units.
        polkit.addRule(function(action, subject) {
          var units = ${builtins.toJSON units};
          if (action.id === "org.freedesktop.systemd1.manage-units" &&
              subject.user === "strata-control" &&
              units.indexOf(action.lookup("unit")) !== -1) {
            var verb = action.lookup("verb");
            if (verb === "start" || verb === "stop") {
              return polkit.Result.YES;
            }
          }
        });
      ''
      + lib.optionalString (wake && cfg.wake.powerOff) ''
        // strata-wake-control powers off an owner the gateway woke, after its own checks
        // (no local login, SSH session, Docker container or heavy job).
        polkit.addRule(function(action, subject) {
          if (subject.user === "strata-control" &&
              (action.id === "org.freedesktop.login1.power-off" ||
               action.id === "org.freedesktop.login1.power-off-multiple-sessions")) {
            return polkit.Result.YES;
          }
        });
      '';
    }
  );
}
