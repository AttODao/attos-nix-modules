{
  config,
  lib,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.modules.attos-jobs;
in
{
  imports = [ ./nixos.nix ];

  options.modules.attos-jobs = {
    enable = lib.mkEnableOption "attos-jobs, a root agent and CLI that list and stop the work other hosts run here (heavy jobs, Forgejo Actions job containers, remote login sessions, selected units)";
    socketGroup = mkOption {
      type = types.nullOr types.nonEmptyStr;
      default = null;
      description = "Existing consumer group whose members may stop items, pause and resume through /run/attos-jobs/control.sock; required when enabled. Listing needs no group: the status file is world-readable.";
    };
    units = mkOption {
      type = types.listOf types.nonEmptyStr;
      default = [ ];
      example = [ "strata-headless-iq3-s.service" ];
      description = "System units shown (while active) and stoppable as remote work. The strata module adds its model units.";
    };
    pauseUnits = mkOption {
      type = types.listOf types.nonEmptyStr;
      defaultText = lib.literalExpression ''lib.optional config.modules.forgejo-actions-runner.enable "forgejo-runner-default.service"'';
      description = "Units stopped by `attos-jobs pause` and started by `resume`, so this host takes no new jobs. Stopping the Forgejo runner cancels the CI job it is running; another runner picks up new jobs.";
    };
    originNames = mkOption {
      type = types.attrsOf types.nonEmptyStr;
      default = { };
      example = {
        "10.252.0.1" = "hermes";
      };
      description = "Display names for the remote addresses of login sessions.";
    };
    noctalia = {
      enable = lib.mkEnableOption "the attos-jobs Noctalia bar widget and panel (needs modules.noctalia); the panel also opens when a shutdown waits for remote work";
      plugin = mkOption {
        type = types.package;
        internal = true;
        readOnly = true;
        description = "Noctalia path-source directory holding the attos/jobs plugin.";
      };
    };
  };

  config = {
    modules.attos-jobs.pauseUnits = lib.mkOptionDefault (
      lib.optional config.modules.forgejo-actions-runner.enable "forgejo-runner-default.service"
    );
    assertions = lib.mkIf cfg.enable [
      {
        assertion = cfg.socketGroup != null;
        message = "modules.attos-jobs.socketGroup is required when attos-jobs is enabled.";
      }
      {
        assertion = !cfg.noctalia.enable || config.modules.noctalia.enable;
        message = "modules.attos-jobs.noctalia needs modules.noctalia.";
      }
    ];
  };
}
