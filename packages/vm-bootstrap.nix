{
  pkgs,
  incus,
  virtualMachines,
}:
let
  config = pkgs.writeText "vm-bootstrap.json" (builtins.toJSON { inherit virtualMachines; });
in
pkgs.writeShellApplication {
  name = "vm-bootstrap";
  runtimeInputs = [ incus ];
  text = ''
    export PYTHONPATH=${pkgs.writeTextDir "rebuild.py" (builtins.readFile ../modules/incus/rebuild.py)}
    export PYTHONDONTWRITEBYTECODE=1
    exec ${pkgs.python3}/bin/python3 ${../modules/incus/bootstrap.py} --config ${config} "$@"
  '';
}
