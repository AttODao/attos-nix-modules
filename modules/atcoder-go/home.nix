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
  scaffold = cfg.projectAssets != null;
  projectAssets = pkgs.runCommand "atcoder-go-project-assets" { } ''
    mkdir -p "$out/.atcoder"
    cp -R ${lib.escapeShellArg "${cfg.projectAssets}/atcoder/."} "$out/.atcoder/"
    cp ${lib.escapeShellArg "${cfg.projectAssets}/devenv.nix"} "$out/devenv.nix"
    cp ${lib.escapeShellArg "${cfg.projectAssets}/devenv.yaml"} "$out/devenv.yaml"
    cp ${lib.escapeShellArg "${cfg.projectAssets}/envrc"} "$out/.envrc"
    cp ${lib.escapeShellArg "${cfg.projectAssets}/gitignore"} "$out/.gitignore"
  '';
  # The scaffold uses its own toolchain; the minimal CLI follows the user's Go.
  goPackage = if scaffold then cfg.projectGoPackage else config.programs.go.package;
  atcoderGo =
    pkgs.runCommand "atcoder-go"
      {
        nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
        meta.mainProgram = "atcoder-go";
      }
      ''
        makeBinaryWrapper ${lib.getExe attopkgs.atcoder-go} "$out/bin/atcoder-go" \
          --set ATCODER_GO_BIN_DIR ${goPackage}/bin \
          ${lib.optionalString scaffold "--set ATCODER_PROJECT_ASSETS ${projectAssets}"}
      '';
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
    home.packages = lib.optional cfg.devenv.enable pkgs.devenv ++ [
      pkgs.gopls
      attopkgs.atcoder-cli
      attopkgs.atcoder-oj
      attopkgs.atcoder-aclogin
      atcoderGo
    ];
  };
}
