# pipeasioとumuは固定依存なので、PATHとdriver pathをwrapperで渡す。
{
  lib,
  build-go-program,
  runCommand,
  makeBinaryWrapper,
  pipeasio,
  umu-launcher,
}:
let
  unwrapped = build-go-program {
    pname = "pipeasio-steam-prefixes";
    src = ./.;
  };
in
runCommand "pipeasio-steam-prefixes"
  {
    nativeBuildInputs = [ makeBinaryWrapper ];
    meta = {
      description = "Register PipeASIO in existing Steam Proton prefixes";
      mainProgram = "pipeasio-register-steam-prefixes";
      platforms = lib.platforms.linux;
    };
  }
  ''
    makeBinaryWrapper ${lib.getExe unwrapped} "$out/bin/pipeasio-register-steam-prefixes" \
      --prefix PATH : ${
        lib.makeBinPath [
          pipeasio
          umu-launcher
        ]
      } \
      --set PIPEASIO_DRIVER_DLL ${pipeasio}/lib/wine/x86_64-windows/pipeasio64.dll \
      --set PIPEASIO_PROTON_RUN "$out/bin/pipeasio-proton-run"
    makeBinaryWrapper ${lib.getExe unwrapped} "$out/bin/pipeasio-proton-run" \
      --prefix PATH : ${lib.makeBinPath [ umu-launcher ]} \
      --add-flags proton-run
  ''
