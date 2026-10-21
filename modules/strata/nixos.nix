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
      user = ps.require "strata" "user" cfg.user;
      group = config.users.users.${user}.group;
      root = ps.require "strata" "dataDir" cfg.dataDir;
      keyFile = ps.require "strata" "apiKeyFile" cfg.apiKeyFile;
      flavor = ps.require "strata" "flavor" cfg.flavor;
      images = {
        rocm-gfx110x = "ghcr.io/niko1221/strata:0.2.2-rocm-gfx110x@sha256:99ae1768abd51d14ad684f751f42a256ad5f41079adf3ec5da04673c659ebc5b";
        rocm-gfx120x = "ghcr.io/niko1221/strata:0.2.2-rocm-gfx120x@sha256:e589426a995289a0ccffe601fb8791f07a2c5279729a593e7f23c60ee951f5ff";
        rocm-gfx1151 = "ghcr.io/niko1221/strata:0.2.2-rocm-gfx1151@sha256:a7bd04a4451afeae2483b7e5230c66230b9b1c6748a7fea36a3c90f0c65e2e11";
      };
      name = model: "strata-headless-${lib.toLower (lib.replaceStrings [ "_" "." ] [ "-" "-" ] model)}";
      names = map name cfg.models;
      units = map (n: "${n}.service") names;
      endpoint = ps.listen s 8080;
      healthAddress =
        if lib.hasInfix ":" endpoint.address then "[${endpoint.address}]" else endpoint.address;
      sessionPackage = attopkgs.strata-headless-session {
        sessionConfig = {
          systemctl = "${pkgs.systemd}/bin/systemctl";
          setterm = "${pkgs.util-linux}/bin/setterm";
          endpoint = ps.url s 8080;
          healthUrl = "http://${healthAddress}:${toString endpoint.port}/health";
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
            # The desktop app shares <dataDir>/Strata-data as its models folder; hand over files an older root container wrote.
            ${pkgs.findutils}/bin/find ${q root} -xdev \( ! -user ${q user} -o ! -group ${q group} \) \
              -exec ${pkgs.coreutils}/bin/chown -h ${q "${user}:${group}"} {} +
            ${sessionPackage.python}/bin/python ${sessionPackage}/libexec/prepare.py ${q keyFile} ${q runtime} "$(${pkgs.coreutils}/bin/id -g ${q user})"
          '';
          run = pkgs.writeShellScript "${n}-run" ''
            set -euo pipefail
            exec > >(${pkgs.coreutils}/bin/tee -a ${q "${runtime}/console.log"}) 2>&1
            # Upstream HEALTHCHECK passes its key in argv; use unauthenticated /health in the session instead.
            # Run as the session user so the desktop app can use the same model files.
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
      systemd.services = lib.listToAttrs services;
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
      '';
    }
  );
}
