{
  osConfig,
  config,
  lib,
  ...
}:
let
  cfg = osConfig.modules.userDirs;
  homeDirectory = config.home.homeDirectory;
  dataDirectory = if cfg.dataDirectory == null then homeDirectory else cfg.dataDirectory;
in
{
  config = lib.mkIf cfg.enable {
    xdg = {
      enable = true;
      userDirs = {
        enable = true;
        createDirectories = lib.mkDefault true;
        documents = lib.mkDefault "${dataDirectory}/Documents";
        download = lib.mkDefault "${dataDirectory}/Downloads";
        music = lib.mkDefault "${dataDirectory}/Music";
        pictures = lib.mkDefault "${dataDirectory}/Pictures";
        videos = lib.mkDefault "${dataDirectory}/Videos";
      };
    };
  };
}
