{
  osConfig,
  config,
  lib,
  attopkgs,
  ...
}:
{
  config = lib.mkIf osConfig.modules.pandora-launcher.enable {
    home.packages = [
      attopkgs.pandora-launcher
      attopkgs.pandoragh
    ];
  };
}
