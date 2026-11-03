{
  config,
  lib,
  options,
  ps,
  ...
}:
let
  cfg = config.modules.forgejo-actions-runner;
  forgejo = ps.entries config "forgejo";
  localForgejo = ps.select config "forgejo";
  local = localForgejo.standalone || lib.any (entry: ps.isLocal config entry.cfg) forgejo;
  # Guests pinned to an older nixpkgs import this module too; define the runner only where it exists.
  supported = options.services ? forgejo-runner;
in
{
  # jobはこのhostで動く。このhostを信頼して任せられるworkflowのownerだけにForgejoでrunnerを登録する。
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = supported;
            message = "modules.forgejo-actions-runner needs a nixpkgs with services.forgejo-runner.";
          }
          {
            assertion = cfg.uuid != null && cfg.tokenFile != null;
            message = "modules.forgejo-actions-runner.uuid and tokenFile must be supplied when enabled.";
          }
        ];
      }
      (lib.optionalAttrs supported {
        services.forgejo-runner.instances.default = {
          enable = true;
          settings = {
            server.connections.default = {
              url = lib.mkDefault (
                if cfg.url != null then
                  cfg.url
                else if localForgejo.standalone then
                  ps.url localForgejo 3000
                else if builtins.length forgejo == 1 then
                  "https://${(builtins.head forgejo).hostname}"
                else
                  throw "Forgejo runner: register exactly one Forgejo hostname or set the native runner connection URL."
              );
              inherit (cfg) uuid;
            };
            runner = {
              fetch_interval = lib.mkIf (cfg.fetchInterval != null) cfg.fetchInterval;
              name = lib.mkDefault config.networking.hostName;
              labels = lib.mkIf cfg.docker (
                lib.mkDefault [
                  "ubuntu-latest:docker://ghcr.io/catthehacker/ubuntu:act-24.04@sha256:62d572b92f9f32d3427b6d220ad1f9dca9c7b6ffad37d295425037dbff78abaf"
                  "docker:docker://node:24.22.2-bookworm@sha256:e7add2a490bb17d97b485b8641bd88455fff7839ade0f5eba493c3508124d413"
                ]
              );
            };
            # Jobs get the host Docker socket only when the consumer opts in via dockerHost.
            container = {
              docker_host = lib.mkIf cfg.docker (
                lib.mkDefault (if cfg.dockerHost == null then "-" else cfg.dockerHost)
              );
              options = lib.mkIf (cfg.docker && (cfg.jobLimits.cpus != null || cfg.jobLimits.memory != null)) (
                lib.mkDefault (
                  lib.concatStringsSep " " (
                    lib.optional (cfg.jobLimits.cpus != null) "--cpus=${toString cfg.jobLimits.cpus}"
                    ++ lib.optionals (cfg.jobLimits.memory != null) [
                      "--memory=${cfg.jobLimits.memory}"
                      "--memory-swap=${cfg.jobLimits.memory}"
                    ]
                  )
                )
              );
            };
          };
          secrets.server.connections.default.token_url = cfg.tokenFile;
        };

        systemd.services.forgejo-runner-default = {
          unitConfig.ConditionPathExists = lib.mkDefault [ cfg.tokenFile ];
          wants = lib.optional local "forgejo.service";
          after = lib.optional local "forgejo.service";
        };
      })
    ]
  );
}
