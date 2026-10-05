{
  python3,
  writeTextFile,
  symlinkJoin,
}:
let
  core = writeTextFile {
    name = "pandoragh-core-source";
    destination = "/share/pandoragh/pandoragh_core.py";
    text = builtins.readFile ../modules/pandora-launcher/pandoragh_core.py;
  };
  bin = writeTextFile {
    name = "pandoragh-bin";
    destination = "/bin/pandoragh";
    executable = true;
    text =
      builtins.replaceStrings
        [ "@PYTHON@" "@PANDORAGH_CORE@" ]
        [ "${python3}/bin/python3" "${core}/share/pandoragh/pandoragh_core.py" ]
        (builtins.readFile ../modules/pandora-launcher/pandoragh.py);
  };
in
symlinkJoin {
  name = "pandoragh";
  paths = [
    bin
    core
  ];
}
