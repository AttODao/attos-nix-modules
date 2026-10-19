{ config, lib, ... }:
let
  ps = import ../public-services/lib.nix { inherit lib; };
  s = ps.select config "attos-hoyo-dashboard";
in
{
  imports = [ ./nixos.nix ];

  options.modules = ps.moduleOptions "attos-hoyo-dashboard" (
    ps.common "AttOsHoYoDashboard HoYoLAB dashboard"
    // {
      dataDir = ps.pathOption "Persistent root containing the PostgreSQL postgres/ directory.";
      environmentFile = ps.pathOption "Runtime environment file for the app and PostgreSQL: DB_PASSWORD and the same value as POSTGRES_PASSWORD, HOYOLAB_COOKIE_KEY and the first-start INITIAL_ADMIN_PASSWORD.";
      initialAdminUsername = lib.mkOption {
        type = lib.types.strMatching "[A-Za-z0-9._-]{1,64}";
        default = "admin";
        description = "Administrator created on first start while no users exist; changing it later does not rename existing users.";
      };
    }
  );

  config = lib.mkMerge [
    { assertions = s.assertions; }
    (lib.mkIf s.enabled {
      modules.docker.enable = true;
    })
  ];
}
