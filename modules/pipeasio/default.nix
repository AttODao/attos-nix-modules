{ config, lib, ... }:
{
  imports = [
    ./nixos.nix
    ../pipewire
    ../steam
  ];

  options.modules.pipeasio.enable = lib.mkEnableOption "shared PipeASIO Steam prefix registration";

  config = lib.mkIf config.modules.pipeasio.enable {
    modules.pipewire.enable = true;
    modules.steam.enable = true;
    home-manager.sharedModules = [ ./home.nix ];
  };
}
