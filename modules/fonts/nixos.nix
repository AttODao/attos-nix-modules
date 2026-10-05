{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = lib.mkIf config.modules.fonts.enable {
    fonts = {
      enableDefaultPackages = lib.mkDefault true;
      packages = with pkgs; [
        nerd-fonts.inconsolata
        noto-fonts-cjk-sans
        noto-fonts-cjk-serif
      ];
      fontconfig.defaultFonts = lib.mkDefault {
        sansSerif = [ "Noto Sans CJK JP" ];
        serif = [ "Noto Serif CJK JP" ];
        monospace = [ "Inconsolata Nerd Font Mono" ];
      };
    };
  };
}
