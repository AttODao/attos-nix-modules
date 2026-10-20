# go.modを持たない単一 `package main` を、ビルド時だけGoを使って1つの実行ファイルにする。
# 標準libraryのみ。`*_test.go` があればcheckPhaseで `go test` する。
{
  lib,
  stdenvNoCC,
  go,
}:
{
  pname,
  src,
  meta ? { },
}:
stdenvNoCC.mkDerivation {
  inherit pname;
  version = "0";
  src = lib.fileset.toSource {
    root = src;
    fileset = lib.fileset.fileFilter (file: file.hasExt "go") src;
  };
  nativeBuildInputs = [ go ];
  env = {
    CGO_ENABLED = "0";
    GOFLAGS = "-trimpath";
    GOTOOLCHAIN = "local";
  };
  configurePhase = ''
    export HOME=$TMPDIR GOCACHE=$TMPDIR/go-cache GOPATH=$TMPDIR/go
  '';
  buildPhase = ''
    runHook preBuild
    sources=$(find . -maxdepth 1 -type f -name '*.go' ! -name '*_test.go' | sort)
    go vet $sources
    go build -ldflags='-s -w' -o ${pname} $sources
    runHook postBuild
  '';
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    if [ -n "$(find . -maxdepth 1 -type f -name '*_test.go')" ]; then
      go test $(find . -maxdepth 1 -type f -name '*.go' | sort)
    fi
    runHook postCheck
  '';
  installPhase = ''
    install -Dm755 ${pname} $out/bin/${pname}
  '';
  meta = {
    mainProgram = pname;
    platforms = lib.platforms.linux;
  }
  // meta;
}
