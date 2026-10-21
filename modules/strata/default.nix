{
  config,
  lib,
  ps,
  ...
}:
let
  s = ps.select config "strata";
in
{
  imports = [ ./nixos.nix ];

  options.modules = ps.moduleOptions "strata" (
    ps.common "Strata on-demand AMD LLM API"
    // {
      flavor = lib.mkOption {
        type = lib.types.nullOr (
          lib.types.enum [
            "rocm-gfx110x"
            "rocm-gfx120x"
            "rocm-gfx1151"
          ]
        );
        default = null;
        description = "AMD image flavor matching the GPU; required for local deployment.";
      };
      dataDir = ps.pathOption "Persistent /data volume (models, prepared packs, tuning and state).";
      models = lib.mkOption {
        type = lib.types.addCheck (lib.types.listOf (lib.types.strMatching "[A-Za-z0-9][A-Za-z0-9_.-]*")) (
          xs: xs != [ ]
        );
        default = [ "IQ3_S" ];
        example = [
          "IQ3_S"
          "IQ3_XXS"
          "Q2_0"
        ];
        description = "MODEL identifiers offered by the session; the first starts after ten seconds.";
      };
      context = lib.mkOption {
        type = lib.types.nullOr lib.types.nonEmptyStr;
        default = null;
        description = "CONTEXT passed to Strata, such as 32k; null lets Strata choose.";
      };
      apiKeyFile = ps.pathOption "Runtime root:root 0400 file containing only the API key; required locally.";
      user = lib.mkOption {
        type = lib.types.nullOr lib.types.nonEmptyStr;
        default = null;
        description = "Consumer-owned account running the greeter session and permitted to start/stop model units.";
      };
    }
  );

  config = lib.mkMerge [
    { assertions = s.assertions; }
    (lib.mkIf s.enabled { modules.docker.enable = true; })
  ];
}
