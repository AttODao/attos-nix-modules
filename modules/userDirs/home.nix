{
  osConfig,
  config,
  lib,
  ...
}:
let
  cfg = osConfig.modules.userDirs;
  homeDirectory = if cfg.homeDirectory == null then config.home.homeDirectory else cfg.homeDirectory;
  dataDirectory = if cfg.dataDirectory == null then homeDirectory else cfg.dataDirectory;
in
{
  config = lib.mkIf cfg.enable {
    xdg = {
      enable = true;
      userDirs = {
        enable = true;
        createDirectories = true;
        desktop = "${homeDirectory}/Desktop";
        documents = "${dataDirectory}/Documents";
        download = "${dataDirectory}/Downloads";
        music = "${dataDirectory}/Music";
        pictures = "${dataDirectory}/Pictures";
        publicShare = "${homeDirectory}/Public";
        templates = "${homeDirectory}/Templates";
        videos = "${dataDirectory}/Videos";
      };
    };
  };
}
