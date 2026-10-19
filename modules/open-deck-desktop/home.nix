{
  lib,
  attopkgs,
  osConfig,
  ...
}:
{
  config = lib.mkIf osConfig.modules.open-deck-desktop.enable {
    home.packages = [ attopkgs.open-deck-desktop ];
  };
}
