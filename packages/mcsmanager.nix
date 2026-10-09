{
  lib,
  fetchurl,
  stdenvNoCC,
  autoPatchelfHook,
  stdenv,
  nodejs,
}:
stdenvNoCC.mkDerivation rec {
  pname = "mcsmanager";
  version = "10.19.0";
  src = fetchurl {
    url = "https://github.com/MCSManager/MCSManager/releases/download/v${version}/mcsmanager_linux_release.tar.gz";
    hash = "sha256-ONYOkOYcICfQUZ7/ATZkFqopYFwIjVqpSH1Btsblkkw=";
  };
  # The official release app.js bundles dependencies and languages; install.sh
  # explicitly requires no npm installation. No mutable npm downloads are needed.
  nativeBuildInputs = [
    autoPatchelfHook
    nodejs
  ];
  buildInputs = [ stdenv.cc.cc.lib ];
  dontBuild = true;
  postPatch = ''
    # Upstream logs the daemon authentication secret to stdout AND its log file.
    substituteInPlace daemon/app.js --replace-fail \
      'log_1.default.info((0, i18n_1.$t)("TXT_CODE_app.password", { key: config.key }));' \
      '/* Authentication secrets must not be logged. */'
    # Immutable packaged helpers already have executable permissions.
    substituteInPlace daemon/app.js \
      --replace-fail 'fs_extra_1.default.chmodSync(const_1.GOLANG_ZIP_PATH, 0o755);' "" \
      --replace-fail 'fs_extra_1.default.chmodSync(const_1.PTY_PATH, 0o755);' ""
    substituteInPlace daemon/app.js --replace-fail \
      'console.error(`Failed to stop upload writer for key ''${key}:`, e);' \
      'console.error("Failed to stop upload writer");'
  '';
  installPhase = ''
    runHook preInstall
    dest="$out/share/mcsmanager"
    mkdir -p "$dest"/{web,daemon/lib}
    cp web/app.js web/package.json "$dest/web/"
    cp -r web/public "$dest/web/"
    cp daemon/app.js daemon/package.json "$dest/daemon/"
    cp daemon/lib/*license.txt "$dest/daemon/lib/"
    for tool in pty file_zip 7z; do
      cp "daemon/lib/''${tool}_linux_${
        if stdenv.hostPlatform.isAarch64 then "arm64" else "x64"
      }" "$dest/daemon/lib/"
    done
    chmod 755 "$dest"/daemon/lib/*_linux_*
    runHook postInstall
  '';
  doInstallCheck = true;
  installCheckPhase = ''
    node --check "$out/share/mcsmanager/web/app.js"
    node --check "$out/share/mcsmanager/daemon/app.js"
    if grep -F 'TXT_CODE_app.password", { key: config.key }' "$out/share/mcsmanager/daemon/app.js"; then
      echo "Unsafe daemon secret logging remains" >&2
      exit 1
    fi
    node ${../modules/mcsmanager/test-smoke.cjs} "$out/share/mcsmanager" ${../modules/mcsmanager/bootstrap.cjs}
  '';
  meta = {
    description = "MCSManager native web panel and daemon";
    homepage = "https://mcsmanager.com/";
    license = lib.licenses.asl20;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
