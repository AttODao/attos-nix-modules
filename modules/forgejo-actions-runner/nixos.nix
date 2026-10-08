{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.modules.forgejo-actions-runner;
  ps = import ../public-services/lib.nix { inherit lib; };
  require = field: ps.require "modules.forgejo-actions-runner" field cfg.${field};
  dataDir = require "dataDir";
  tokenFile = require "tokenFile";
  forgejo = ps.entries config "forgejo";
  localForgejo = ps.select config "forgejo";
in
{
  config = lib.mkIf cfg.enable {
    assertions =
      map
        (field: {
          assertion = cfg.${field} != null;
          message = "modules.forgejo-actions-runner.${field} must be supplied when enabled.";
        })
        [
          "tokenFile"
          "dataDir"
        ]
      ++ [
        {
          assertion = !cfg.dynamicUser || dataDir == "/var/lib/gitea-runner/forgejo";
          message = "Forgejo runner: dynamicUser requires the native /var/lib/gitea-runner/forgejo StateDirectory.";
        }
      ];

    services.gitea-actions-runner = {
      package = lib.mkDefault pkgs.forgejo-runner;
      instances.forgejo = {
        enable = true;
        name = lib.mkDefault config.networking.hostName;
        url = lib.mkDefault (
          if localForgejo.standalone then
            ps.url localForgejo 3000
          else if builtins.length forgejo == 1 then
            "https://${(builtins.head forgejo).hostname}"
          else
            throw "Forgejo runner: register exactly one Forgejo hostname or set the native runner instance URL."
        );
        tokenFile = lib.mkDefault tokenFile;
        labels = lib.mkDefault [
          "ubuntu-latest:docker://node:24.21.0-bookworm@sha256:64af3819f9275802414d7cdc38c27e9d82bd564dec4d4da87d008255d36c63b4"
          "docker:docker://node:24.21.0-bookworm@sha256:64af3819f9275802414d7cdc38c27e9d82bd564dec4d4da87d008255d36c63b4"
        ];
      };
    };

    # The native module has no dataDir and hardcodes both registration and
    # daemon paths. Bind the selected directory there without moving its state.
    # A static service identity avoids recycled DynamicUser ownership outside
    # systemd's managed StateDirectory.
    users.groups.gitea-runner = lib.mkIf (!cfg.dynamicUser) { };
    users.users.gitea-runner = lib.mkIf (!cfg.dynamicUser) {
      isSystemUser = true;
      group = lib.mkDefault "gitea-runner";
    };

    systemd.tmpfiles.settings."10-forgejo-actions-runner" = lib.mkIf (!cfg.dynamicUser) {
      ${dataDir}.d = {
        mode = lib.mkDefault "0700";
        user = lib.mkDefault "gitea-runner";
        group = lib.mkDefault "gitea-runner";
      };
    };

    systemd.services.gitea-runner-forgejo = {
      wants = lib.optional (
        localForgejo.standalone || lib.any (entry: ps.isLocal config entry.cfg) forgejo
      ) "docker-forgejo.service";
      after = lib.optional (
        localForgejo.standalone || lib.any (entry: ps.isLocal config entry.cfg) forgejo
      ) "docker-forgejo.service";
      unitConfig = {
        ConditionPathExists = lib.mkDefault [ tokenFile ];
        RequiresMountsFor = lib.mkDefault ([ dataDir ] ++ cfg.requiresMountsFor);
      };
      serviceConfig = {
        # The native ordinary assignment needs an override for the public choice.
        DynamicUser = lib.mkForce cfg.dynamicUser;
        BindPaths = lib.mkIf (!cfg.dynamicUser) (
          lib.mkDefault [ "${dataDir}:/var/lib/gitea-runner/forgejo" ]
        );
      };
    };
  };
}
