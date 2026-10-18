{ config, lib, ... }:
{
  options.modules.immich-client = {
    enable = lib.mkEnableOption "Immich CLI uploader that watches local directories";
    watchDirectories = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "/mnt/photos" ];
      description = "Directories uploaded recursively at start and watched for new media. Sign in once with `immich login <url> <api-key>`; credentials are never managed declaratively.";
    };
  };

  config = lib.mkIf config.modules.immich-client.enable {
    assertions = [
      {
        assertion = config.modules.immich-client.watchDirectories != [ ];
        message = "modules.immich-client.watchDirectories must not be empty when modules.immich-client.enable is true.";
      }
    ];
    home-manager.sharedModules = [ ./home.nix ];
  };
}
