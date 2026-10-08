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
      default = ./assets;
      defaultText = lib.literalExpression "./assets";
      description = "Complete project scaffold; defaults to the module's bundled scripts, templates, snippet and devenv definitions. Null selects only the minimal shared helpers.";
    };
    projectGoPackage = lib.mkOption {
      type = lib.types.package;
      default = config.modules.atcoder-go.goPackage;
      defaultText = lib.literalExpression "config.modules.atcoder-go.goPackage";
      description = "Go toolchain used by the project scaffold's atcoder-go command.";
    };
  };

  config = lib.mkIf config.modules.atcoder-go.enable {
    modules.zsh.enable = true;
    home-manager.sharedModules = [ ./home.nix ];
  };
}
