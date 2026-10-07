{
  lib,
  fetchFromGitHub,
  python3Packages,
}:

python3Packages.buildPythonApplication rec {
  pname = "aclogin";
  version = "0.2.1";
  format = "setuptools";

  src = fetchFromGitHub {
    owner = "key-moon";
    repo = "aclogin";
    rev = "e461311c0326578b16d1488be84261f4b24f6134";
    hash = "sha256-kyU7KpFenFb7obwSrDp6dPfuE+36r0BGYerrJj3+EyA=";
  };

  dependencies = with python3Packages; [
    appdirs
  ];

  nativeBuildInputs = with python3Packages; [
    setuptools
  ];

  meta = {
    description = "Save AtCoder session cookies for command line tools";
    homepage = "https://github.com/key-moon/aclogin";
    license = lib.licenses.mit;
    mainProgram = "aclogin";
  };
}
