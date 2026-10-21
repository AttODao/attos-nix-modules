{
  lib,
  attopkgs,
  osConfig,
  ...
}:
let
  cfg = osConfig.modules.strata-desktop;
in
{
  config = lib.mkIf cfg.enable {
    home.packages = [ (attopkgs.strata-desktop.override { inherit (cfg) sharePort; }) ];
  };
}
