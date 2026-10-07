{
  config,
  lib,
  pkgs,
  attopkgs,
  ...
}:
let
  users = config.modules.home-manager.users;
in
{
  options.modules.home-manager.backupFileExtension = lib.mkOption {
    type = lib.types.nullOr lib.types.nonEmptyStr;
    default = null;
    description = "Suffix for Home Manager backups of existing files; null disables backups.";
  };

  options.modules.home-manager.users = lib.mkOption {
    type = lib.types.listOf lib.types.nonEmptyStr;
    default = [ ];
    example = [ "attodao" ];
    description = "Existing NixOS users managed by Home Manager; enabled shared features apply to every HM user.";
  };

  config = {
    _module.args.attopkgs = import ../../packages { inherit pkgs; };

    assertions = [
      {
        assertion = builtins.length users == builtins.length (lib.unique users);
        message = "modules.home-manager.users must not contain duplicate users.";
      }
    ]
    ++ map (user: {
      assertion =
        user == "root"
        || (lib.attrByPath [ "users" "users" user "isNormalUser" ] false config)
        || (lib.attrByPath [ "users" "users" user "isSystemUser" ] false config);
      message = "modules.home-manager.users: '${user}' must be declared in users.users as a normal or system user.";
    }) users;

    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      backupFileExtension = lib.mkDefault config.modules.home-manager.backupFileExtension;
      extraSpecialArgs = { inherit attopkgs; };
      users = lib.genAttrs users (_: { });
      sharedModules = [
        {
          # Keep this compatibility baseline fixed when Home Manager is updated.
          home.stateVersion = lib.mkDefault "26.05";
          programs.home-manager.enable = true;
        }
      ];
    };
  };
}
