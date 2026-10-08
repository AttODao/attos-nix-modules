{ config, lib, ... }:
let
  ps = import ../public-services/lib.nix { inherit lib; };
  s = ps.select config "karakeep";
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

  options.modules = ps.moduleOptions "karakeep" (
    ps.common "shared Karakeep service"
    // {
      dataDir = ps.pathOption "Persistent root containing Karakeep data/ and meilisearch/ directories.";
      environmentFile = ps.pathOption "Runtime environment file for Karakeep and Meilisearch; supply secrets here.";
      environment = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Nonsecret Karakeep application settings, including inference/embedding endpoints and models. Credentials belong in environmentFile, never here.";
      };
      dataUid = ownership "UID owning Karakeep data and Meilisearch directories; must match the container images or standard OCI user overrides.";
      dataGid = ownership "GID owning Karakeep data and Meilisearch directories; must match the container images or standard OCI user overrides.";
    }
  );

  config = lib.mkMerge [
    { assertions = s.assertions; }
    (lib.mkIf s.enabled {
      modules.docker.enable = true;
      modules.swarm.enable = lib.mkIf (!s.standalone) true;
    })
  ];
}
