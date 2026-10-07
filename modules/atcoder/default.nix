{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [ ../zsh ];

  options.modules.atcoder = {
    enable = lib.mkEnableOption "shared AtCoder Go tools and commands";
    goPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.go;
      defaultText = lib.literalExpression "pkgs.go";
      description = "Global Go package for all HM users; independent of the optional project wrapper toolchain.";
    };
    nixDirenv.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Use nix-direnv for the shared direnv setup.";
    };
    projectAssets = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Complete consumer-owned scaffold directory containing atcoder/, devenv.nix, devenv.yaml, envrc and gitignore. When supplied, package its atcoder/scripts/project as the preferred atcoder-go command.";
    };
    projectGoPackage = lib.mkOption {
      type = lib.types.package;
      default = config.modules.atcoder.goPackage;
      defaultText = lib.literalExpression "config.modules.atcoder.goPackage";
      description = "Go toolchain used by the consumer scaffold's atcoder-go command.";
    };
  };

  config = lib.mkIf config.modules.atcoder.enable {
    modules.zsh.enable = true;
    home-manager.sharedModules = [ ./home.nix ];
  };
}
