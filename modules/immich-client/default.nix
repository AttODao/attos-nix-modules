{ config, lib, ... }:
{
  options.modules.immich-client = {
    enable = lib.mkEnableOption "Immich CLI uploader that watches local directories";
    watchDirectories = lib.mkOption {
      type = lib.types.nullOr (lib.types.nonEmptyListOf lib.types.str);
      default = null;
      defaultText = lib.literalExpression "[ config.xdg.userDirs.pictures ] of each user";
      example = [ "/mnt/photos" ];
      description = "Directories uploaded recursively at start and watched for new media; null uses each user's XDG Pictures directory. Sign in once with `immich login <url> <api-key>`; credentials are never managed declaratively.";
    };
  };

  config = lib.mkIf config.modules.immich-client.enable {
    home-manager.sharedModules = [ ./home.nix ];
  };
}
