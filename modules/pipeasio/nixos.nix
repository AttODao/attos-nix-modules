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

    # modules.steam enables programs.steam; a consumer-supplied package must add this env itself.
    programs.steam.package = lib.mkDefault (
      pkgs.steam.override {
        extraEnv = {
          # Proton only discovers the Unix bridge when it is added to WINEDLLPATH.
          WINEDLLPATH = "${pipeasio}/lib/wine";
        };
      }
    );
  };
}
