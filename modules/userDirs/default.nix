{ config, lib, ... }:
{
  options.modules.userDirs = {
    enable = lib.mkEnableOption "shared XDG user directories";
    homeDirectory = lib.mkOption {
      type = lib.types.nullOr (lib.types.strMatching "/.*");
      default = null;
      defaultText = lib.literalExpression "each user's home.homeDirectory";
      description = "Quoted absolute runtime directory for Desktop, Public and Templates; not a Nix source path.";
    };
    dataDirectory = lib.mkOption {
      type = lib.types.nullOr (lib.types.strMatching "/.*");
      default = null;
      defaultText = lib.literalExpression "homeDirectory, or each user's home.homeDirectory";
      description = "Quoted absolute runtime directory for Documents, Downloads, Music, Pictures and Videos; not a Nix source path.";
    };
  };

  config = lib.mkIf config.modules.userDirs.enable {
    home-manager.sharedModules = [ ./home.nix ];
  };
}
