{
  config,
  lib,
  options,
  ...
}:
let
  cfg = config.modules.forgejo-actions-runner;
  ps = import ../public-services/lib.nix { inherit lib; };
  forgejo = ps.entries config "forgejo";
  localForgejo = ps.select config "forgejo";
  local = localForgejo.standalone || lib.any (entry: ps.isLocal config entry.cfg) forgejo;
  # Guests pinned to an older nixpkgs import this module too; define the runner only where it exists.
  supported = options.services ? forgejo-runner;
in
{
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
          {
            assertion = !config.boot.isContainer && config.virtualisation.incus.agent.enable;
            message = "Forgejo runner must run inside an Incus virtual-machine guest (boot.isContainer=false and virtualisation.incus.agent.enable=true), never on the physical host or in a container.";
          }
        ];
      }
      (lib.optionalAttrs supported {
        services.forgejo-runner.instances.default = {
          enable = true;
          settings = {
            server.connections.default = {
              url = lib.mkDefault (
                if localForgejo.standalone then
                  ps.url localForgejo 3000
                else if builtins.length forgejo == 1 then
                  "https://${(builtins.head forgejo).hostname}"
                else
                  throw "Forgejo runner: register exactly one Forgejo hostname or set the native runner connection URL."
              );
              inherit (cfg) uuid;
            };
            runner = {
              name = lib.mkDefault config.networking.hostName;
              labels = lib.mkIf cfg.docker (
                lib.mkDefault [
                  "ubuntu-latest:docker://ghcr.io/catthehacker/ubuntu:act-24.04@sha256:62d572b92f9f32d3427b6d220ad1f9dca9c7b6ffad37d295425037dbff78abaf"
                  "docker:docker://node:24.22.0-bookworm@sha256:14078204b6bb268c107ceff6d3c43f45a888105e5c2b18b14c32b3409d93a1b0"
                ]
              );
            };
            # Jobs get the host Docker socket only when the consumer opts in via dockerHost.
            container.docker_host = lib.mkIf cfg.docker (
              lib.mkDefault (if cfg.dockerHost == null then "-" else cfg.dockerHost)
            );
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
