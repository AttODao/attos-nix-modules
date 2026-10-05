{
  config,
  lib,
  attopkgs,
  osConfig,
  ...
}:
{
  config = lib.mkIf osConfig.modules.open-deck-desktop.enable {
    assertions = [
      {
        assertion = osConfig.programs.appimage.enable;
        message = "modules.open-deck-desktop.enable requires programs.appimage.enable in the NixOS configuration.";
      }
    ];

    home.packages = [ attopkgs.open-deck-desktop ];
  };
}
