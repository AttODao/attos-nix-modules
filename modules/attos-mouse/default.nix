{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [ ./nixos.nix ];

  options.modules.attos-mouse = {
    enable = lib.mkEnableOption "shared attos-mouse driver and ring menu";
    settings = lib.mkOption {
      type = (pkgs.formats.toml { }).type;
      default = { };
      description = "attos-mouse config.toml contents (device and menu definitions belong to the consumer), recursively merged over the shared defaults; lists replace.";
    };
  };

  config = lib.mkIf config.modules.attos-mouse.enable {
    home-manager.sharedModules = [ ./home.nix ];
    assertions = [
      {
        assertion = !config.modules.solaar.enable;
        message = "modules.attos-mouse and modules.solaar are exclusive: both divert the same mouse buttons.";
      }
    ];
  };
}
