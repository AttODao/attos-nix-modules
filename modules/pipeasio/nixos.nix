{
  config,
  lib,
  pkgs,
  attopkgs,
  ...
}:
let
  pipeasio = attopkgs.pipeasio;
in
{
  config = lib.mkIf config.modules.pipeasio.enable {
    environment.systemPackages = [ pipeasio ];

    programs.steam.package = lib.mkIf config.programs.steam.enable (
      pkgs.steam.override {
        extraEnv = {
          # Proton only discovers the Unix bridge when it is added to WINEDLLPATH.
          WINEDLLPATH = "${pipeasio}/lib/wine";
        };
      }
    );
  };
}
