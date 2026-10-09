{
  writeShellApplication,
  writeText,
  python3,
  nix,
  incus,
  flakeFile,
  virtualMachines,
}:
let
  config = writeText "vm-rebuild.json" (builtins.toJSON { inherit flakeFile virtualMachines; });
in
writeShellApplication {
  name = "vm-rebuild";
  runtimeInputs = [
    nix
    incus
    python3
  ];
  text = ''exec python3 ${../modules/incus/rebuild.py} --config ${config} "$@"'';
}
