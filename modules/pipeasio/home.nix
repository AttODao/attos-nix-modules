{
  osConfig,
  lib,
  attopkgs,
  ...
}:
let
  register = attopkgs.pipeasio-steam-prefixes;
in
{
  config = lib.mkIf osConfig.modules.pipeasio.enable {
    # Existing Proton prefixes need registry entries that package installation cannot create.
    home.packages = [
      attopkgs.pipeasio
      register
    ];

    home.activation.registerPipeasioSteamPrefixes = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      run ${lib.getExe register} --skip-registered --no-runtime-download
    '';
  };
}
