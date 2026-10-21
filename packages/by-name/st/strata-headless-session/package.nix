{
  lib,
  stdenvNoCC,
  python3,
  makeWrapper,
  writeText,
}:
{ sessionConfig }:
let
  python = python3.withPackages (ps: [ ps.evdev ]);
  configuration = writeText "strata-session.json" (builtins.toJSON sessionConfig);
in
stdenvNoCC.mkDerivation {
  pname = "strata-headless-session";
  version = "1";
  src = ../../../../modules/strata;
  nativeBuildInputs = [ makeWrapper ];
  dontBuild = true;
  doCheck = true;
  checkPhase = ''
    ${python}/bin/python -m py_compile session.py prepare.py
  '';
  installPhase = ''
    mkdir -p $out/libexec $out/bin $out/share/wayland-sessions
    cp session.py prepare.py $out/libexec/
    makeWrapper ${python}/bin/python $out/bin/strata-headless \
      --add-flags "$out/libexec/session.py ${configuration}"
    makeWrapper $out/bin/strata-headless $out/bin/strata-headless-session --add-flags session
    cat > $out/share/wayland-sessions/strata.desktop <<EOF
    [Desktop Entry]
    Name=Strata (API only)
    Comment=On-demand LLM API on the console
    Exec=$out/bin/strata-headless-session
    Type=Application
    DesktopNames=Strata
    EOF
  '';
  passthru = {
    providedSessions = [ "strata" ];
    inherit python;
  };
  meta = {
    description = "Strata API-only VT session and control CLI";
    platforms = lib.platforms.linux;
  };
}
