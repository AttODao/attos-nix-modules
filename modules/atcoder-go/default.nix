{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [ ../zsh ];

  options.modules.atcoder-go = {
    enable = lib.mkEnableOption "shared AtCoder Go tools and commands";
    devenv.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Install devenv for every HM user. The project scaffold needs it; disable on hosts that supply their own.";
    };
    projectAssets = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = ./assets;
      defaultText = lib.literalExpression "./assets";
      description = "Complete project scaffold (CLI source, templates and devenv definitions) that `atcoder-go init`/`sync` write into a project; defaults to the bundled one. Null disables scaffolding, and init/sync use go.mod as recorded.";
    };
    projectGoPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.go;
      defaultText = lib.literalExpression "pkgs.go";
      description = "Go toolchain the `atcoder-go` command uses while a project scaffold is set; without one it uses each user's `programs.go.package`.";
    };
  };

  config = lib.mkIf config.modules.atcoder-go.enable {
    modules.zsh.enable = true;
    home-manager.sharedModules = [ ./home.nix ];
  };
}
