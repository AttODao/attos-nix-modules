{
  writeShellApplication,
  writeText,
  python3,
  nix,
  incus,
  flakeFile,
  containers,
}:
let
  config = writeText "container-rebuild.json" (builtins.toJSON { inherit flakeFile containers; });
in
writeShellApplication {
  name = "container-rebuild";
  runtimeInputs = [
    nix
    incus
    python3
  ];
  text = ''exec python3 ${../modules/incus/rebuild.py} --config ${config} "$@"'';
}
