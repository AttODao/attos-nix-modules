{ config, lib, ... }:
let
  ps = import ../public-services/lib.nix { inherit lib; };
  selected = ps.select config "sunshine";
in
{
  imports = [
    ./nixos.nix
    ../hyprland
    ../steam
  ];

  options.modules.public-services = ps.option "sunshine" (
    ps.common "Sunshine game streaming host"
    // {
      backendUrl = lib.mkOption {
        type = lib.types.nullOr lib.types.nonEmptyStr;
        default = null;
        description = "Sunshine Web UI upstream reachable by the gateway; required when enabled. Streaming ports are configured separately by the consumer.";
      };
    }
  );

  config = lib.mkMerge [
    { assertions = selected.assertions; }
    (lib.mkIf selected.enabled {
      modules.hyprland.enable = true;
      modules.steam.enable = true;
    })
  ];
}
