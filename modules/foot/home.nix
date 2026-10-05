{
  osConfig,
  config,
  lib,
  ...
}:
{
  config = lib.mkIf osConfig.modules.foot.enable {

    programs.foot = {
      enable = true;
      server.enable = true;
      settings = {
        main.font = lib.mkDefault "Inconsolata Nerd Font Mono:size=11";
        colors-dark.alpha = lib.mkDefault 0.65;
      };
    };
  };
}
