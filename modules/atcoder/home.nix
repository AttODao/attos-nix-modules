{
  osConfig,
  config,
  lib,
  pkgs,
  attopkgs,
  ...
}:
{
  config = lib.mkIf osConfig.modules.atcoder.enable {
    programs.go = {
      enable = lib.mkDefault true;
      # Project-specific toolchain pins use the standard HM package option.
      package = lib.mkDefault pkgs.go;
    };

    programs.direnv = {
      enable = lib.mkDefault true;
      enableZshIntegration = lib.mkDefault true;
      nix-direnv.enable = lib.mkDefault true;
    };

    home.sessionVariables.GOTOOLCHAIN = lib.mkDefault "local";
    home.packages = [
      pkgs.devenv
      pkgs.gopls
      attopkgs.atcoder-cli
      attopkgs.atcoder-oj
      attopkgs.atcoder-aclogin
      (attopkgs.atcoder-commands {
        go = config.programs.go.package;
        homeDirectory = config.home.homeDirectory;
        aclogin = attopkgs.atcoder-aclogin;
      })
    ];
  };
}
