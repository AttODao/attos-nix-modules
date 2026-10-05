{
  osConfig,
  config,
  lib,
  pkgs,
  attopkgs,
  ...
}:
let
  pipeasio = attopkgs.pipeasio;
  protonRun = pkgs.writeShellScript "pipeasio-proton-run" ''
    # umu expects compatdata, while pipeasio-register needs its pfx directory.
    export WINEPREFIX="$STEAM_COMPAT_DATA_PATH"
    exec ${pkgs.umu-launcher}/bin/umu-run "$@"
  '';
  registerSteamPrefixes = pkgs.writeTextFile {
    name = "pipeasio-register-steam-prefixes";
    destination = "/bin/pipeasio-register-steam-prefixes";
    executable = true;
    text =
      builtins.replaceStrings
        [ "@PYTHON@" "@MANAGER@" "@UMU@" "@PROTON_RUN@" "@DRIVER_DLL@" "@PIPEASIO_REGISTER@" ]
        [
          "${pkgs.python3}/bin/python3"
          "${pipeasio}/bin/pipeasio-manage"
          "${pkgs.umu-launcher}/bin/umu-run"
          "${protonRun}"
          "${pipeasio}/lib/wine/x86_64-windows/pipeasio64.dll"
          "${pipeasio}/bin/pipeasio-register"
        ]
        (builtins.readFile ./register-steam-prefixes.py);
  };
in
{
  config = lib.mkIf osConfig.modules.pipeasio.enable {
    # Existing Proton prefixes need registry entries that package installation cannot create.
    home.packages = [
      pipeasio
      registerSteamPrefixes
    ];

    home.activation.registerPipeasioSteamPrefixes = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ${registerSteamPrefixes}/bin/pipeasio-register-steam-prefixes --skip-registered --no-runtime-download
    '';
  };
}
