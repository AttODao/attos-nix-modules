{ pkgs }:
{
  packages = with pkgs; [
    nerd-fonts.inconsolata
    noto-fonts-cjk-sans
    noto-fonts-cjk-serif
  ];
  defaultFonts = {
    sansSerif = [ "Noto Sans CJK JP" ];
    serif = [ "Noto Serif CJK JP" ];
    monospace = [ "Inconsolata Nerd Font Mono" ];
  };
}
