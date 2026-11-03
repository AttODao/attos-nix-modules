{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [ ../pipewire ];

  options.modules.scarlett-driver = {
    enable = lib.mkEnableOption "shared Focusrite Scarlett Solo 4th Gen control daemon, CLI and GUI";
    settings = lib.mkOption {
      type = (pkgs.formats.toml { }).type;
      default = { };
      description = "scarlett-driver daemon config.toml contents (apply_on_connect, apply_phantom, autosave, card, [pipewire], [filter]). Empty uses the daemon defaults.";
    };
  };

  config = lib.mkIf config.modules.scarlett-driver.enable {
    modules.pipewire.enable = true;
    home-manager.sharedModules = [ ./home.nix ];
  };
}
