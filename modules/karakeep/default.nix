{
  config,
  lib,
  ps,
  ...
}:
let
  s = ps.select config "karakeep";
in
{
  imports = [ ./nixos.nix ];

  options.modules = ps.moduleOptions "karakeep" (
    ps.common "shared Karakeep service"
    // {
      dataDir = ps.pathOption "Persistent root whose data/ directory is bind-mounted as the Karakeep state directory (/var/lib/karakeep). Meilisearch keeps its rebuildable index in its own state directory.";
      environmentFile = ps.pathOption "Runtime environment file for Karakeep; must define NEXTAUTH_SECRET and MEILI_MASTER_KEY (the latter also becomes the Meilisearch master key).";
      environment = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = "Nonsecret Karakeep application settings, including inference/embedding endpoints and models. Credentials belong in environmentFile, never here.";
      };
    }
  );

  config.assertions = s.assertions;
}
