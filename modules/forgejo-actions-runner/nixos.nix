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
        ];

    services.gitea-actions-runner = {
      package = lib.mkDefault pkgs.forgejo-runner;
      instances.forgejo = {
        enable = true;
        name = lib.mkDefault config.networking.hostName;
        url = lib.mkDefault (
          if builtins.length forgejo == 1 then
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
    users.groups.gitea-runner = { };
    users.users.gitea-runner = {
      isSystemUser = true;
      group = lib.mkDefault "gitea-runner";
    };

    systemd.tmpfiles.settings."10-forgejo-actions-runner".${dataDir}.d = {
      mode = lib.mkDefault "0700";
      user = lib.mkDefault "gitea-runner";
      group = lib.mkDefault "gitea-runner";
    };

    systemd.services.gitea-runner-forgejo = {
      unitConfig = {
        ConditionPathExists = lib.mkDefault [ tokenFile ];
        RequiresMountsFor = lib.mkDefault [ dataDir ];
      };
      serviceConfig = {
        # Storage plumbing must override the native ordinary assignment.
        DynamicUser = lib.mkForce false;
        BindPaths = lib.mkDefault [ "${dataDir}:/var/lib/gitea-runner/forgejo" ];
      };
    };
  };
}
