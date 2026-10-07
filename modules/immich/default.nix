{ config, lib, ... }:
let
  ps = import ../public-services/lib.nix { inherit lib; };
  s = ps.select config "immich";
in
{
  imports = [ ./nixos.nix ];

  options.modules.public-services = ps.option "immich" (
    ps.common "shared Immich photo service"
    // {
      dataDir = ps.pathOption "Persistent Immich root containing library, postgres, redis and model-cache directories.";
      environmentFile = ps.pathOption "Runtime Immich environment file, including database credentials.";
    }
  );

  config = lib.mkMerge [
    { assertions = s.assertions; }
    (lib.mkIf s.enabled {
      modules.docker.enable = true;
      modules.swarm.enable = true;
    })
  ];
}
