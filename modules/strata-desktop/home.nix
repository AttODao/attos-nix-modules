{
  lib,
  attopkgs,
  osConfig,
  ...
}:
{
  config = lib.mkIf osConfig.modules.strata-desktop.enable {
    home.packages = [ attopkgs.strata-desktop ];
  };
}
