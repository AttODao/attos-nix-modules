{
  lib,
  attopkgs,
  osConfig,
  ...
}:
{
  config = lib.mkIf osConfig.modules.amazon-music.enable {
    home.packages = [ attopkgs.amazon-music ];
  };
}
