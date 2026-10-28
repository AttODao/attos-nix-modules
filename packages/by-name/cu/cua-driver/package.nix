{
  lib,
  stdenv,
  fetchurl,
  autoPatchelfHook,
  libx11,
  libxi,
  libxkbcommon,
}:
stdenv.mkDerivation (finalAttrs: {
  pname = "cua-driver";
  # Hermesのpm/lock.jsonのpinと揃える。Hermesは0.20のruntime contractを要求する。
  version = "0.21.0";

  src = fetchurl {
    url = "https://github.com/trycua/cua/releases/download/cua-driver-rs-v${finalAttrs.version}/cua-driver-rs-${finalAttrs.version}-linux-x86_64-binary.tar.gz";
    hash = "sha256-zym/qtFnN+MecvONrSpkJPJLIaSsLt6oheg8udUDQTU=";
  };
  # tarballは最上位directoryを持たないので、専用directoryへ展開する。
  unpackPhase = ''
    runHook preUnpack
    mkdir source
    tar -xzf "$src" -C source
    runHook postUnpack
  '';
  sourceRoot = "source";
  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [
    libx11
    libxi
    libxkbcommon
    stdenv.cc.cc.lib
  ];
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib/cua-driver" "$out/bin"
    cp -r . "$out/lib/cua-driver/"
    ln -s ../lib/cua-driver/cua-driver "$out/bin/cua-driver"
    ln -s ../lib/cua-driver/cua-cursor-theme "$out/bin/cua-cursor-theme"
    runHook postInstall
  '';
  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    help=$("$out/bin/cua-driver" --help 2>&1)
    [[ "$help" == *"cua-driver ${finalAttrs.version}"* ]]
    printf '%s\n' "$help"
    runHook postInstallCheck
  '';

  meta = {
    description = "Computer-use driver for Hermes Bot Screen";
    homepage = "https://github.com/trycua/cua";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
    mainProgram = "cua-driver";
  };
})
