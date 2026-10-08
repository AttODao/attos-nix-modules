{
  osConfig,
  config,
  lib,
  pkgs,
  ...
}:
let
  common = import ./common.nix { inherit pkgs; };
in
{
  config = lib.mkIf osConfig.modules.fonts.enable {
    home.packages = common.packages;
    fonts.fontconfig = {
      enable = true;
      defaultFonts = lib.mkDefault common.defaultFonts;
    };
  };
}
