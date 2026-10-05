{ config, lib, ... }:
let
  ps = import ../public-services/lib.nix { inherit lib; };
  s = ps.select config "karakeep";
  nullableString =
    description:
    lib.mkOption {
      type = lib.types.nullOr lib.types.nonEmptyStr;
      default = null;
      inherit description;
    };
  ownership =
    description:
    lib.mkOption {
      type = lib.types.nullOr lib.types.ints.unsigned;
      default = null;
      inherit description;
    };
in
{
  imports = [ ./nixos.nix ];

  options.modules.public-services = ps.option "karakeep" (
    ps.common "shared Karakeep service" "http://karakeep:3000"
    // {
      dataDir = ps.pathOption "Persistent root containing Karakeep data/ and meilisearch/ directories.";
      environmentFile = ps.pathOption "Runtime environment file for Karakeep and Meilisearch; supply secrets and optional inference/embedding settings here.";
      dataUid = ownership "UID owning Karakeep data and Meilisearch directories; must match the container images or standard OCI user overrides.";
      dataGid = ownership "GID owning Karakeep data and Meilisearch directories; must match the container images or standard OCI user overrides.";
      networkSubnet = nullableString "Subnet for the private Karakeep bridge network.";
      networkGateway = nullableString "Gateway address for the private Karakeep bridge network.";
      chromeAddress = nullableString "Fixed Chrome container IP within networkSubnet, used by the DevTools API.";
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
