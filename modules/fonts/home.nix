{
  osConfig,
  config,
  lib,
  pkgs,
  ...
}:
{
  config = lib.mkIf osConfig.modules.fonts.enable {
    home.packages = with pkgs; [
      nerd-fonts.inconsolata
      noto-fonts-cjk-sans
      noto-fonts-cjk-serif
    ];
    fonts.fontconfig = {
      enable = true;
      defaultFonts = lib.mkDefault {
        sansSerif = [ "Noto Sans CJK JP" ];
        serif = [ "Noto Serif CJK JP" ];
        monospace = [ "Inconsolata Nerd Font Mono" ];
      };
    };
  };
}
