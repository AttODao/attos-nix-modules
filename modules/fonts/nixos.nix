{
  config,
  lib,
  pkgs,
  ...
}:
let
  common = import ./common.nix { inherit pkgs; };
in
{
  config = lib.mkIf config.modules.fonts.enable {
    fonts = {
      enableDefaultPackages = lib.mkDefault true;
      packages = common.packages;
      fontconfig.defaultFonts = lib.mkDefault common.defaultFonts;
    };
  };
}
