{
  osConfig,
  config,
  lib,
  pkgs,
  attopkgs,
  ...
}:
let
  cfg = osConfig.modules.atcoder-go;
  projectAssets = pkgs.runCommand "atcoder-go-project-assets" { } ''
    mkdir -p "$out/.atcoder"
    cp -R ${lib.escapeShellArg "${cfg.projectAssets}/atcoder/."} "$out/.atcoder/"
    cp ${lib.escapeShellArg "${cfg.projectAssets}/devenv.nix"} "$out/devenv.nix"
    cp ${lib.escapeShellArg "${cfg.projectAssets}/devenv.yaml"} "$out/devenv.yaml"
    cp ${lib.escapeShellArg "${cfg.projectAssets}/envrc"} "$out/.envrc"
    cp ${lib.escapeShellArg "${cfg.projectAssets}/gitignore"} "$out/.gitignore"
  '';
  projectCommand = pkgs.writeShellApplication {
    name = "atcoder-go";
    runtimeInputs = [
      cfg.projectGoPackage
      pkgs.coreutils
      pkgs.gnugrep
    ];
    text = ''
      export ATCODER_GO_BIN_DIR="${cfg.projectGoPackage}/bin"
      export ATCODER_PROJECT_ASSETS="${projectAssets}"
      exec ${pkgs.bash}/bin/bash -euo pipefail ${lib.escapeShellArg "${cfg.projectAssets}/atcoder/scripts/project"} "$@"
    '';
  };
in
{
  config = lib.mkIf osConfig.modules.atcoder-go.enable {
    programs.go = {
      enable = lib.mkDefault true;
      package = lib.mkDefault cfg.goPackage;
    };

    programs.direnv = {
      enable = lib.mkDefault true;
      enableZshIntegration = lib.mkDefault true;
      nix-direnv.enable = lib.mkDefault cfg.nixDirenv.enable;
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
    ]
    ++ lib.optional (cfg.projectAssets != null) (lib.hiPrio projectCommand);
  };
}
