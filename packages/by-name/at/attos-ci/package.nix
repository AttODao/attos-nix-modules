{
  writeShellApplication,
  coreutils,
  findutils,
  gnugrep,
  gnused,
  curl,
  gitMinimal,
  jq,
  nix-update,
  update-nix-fetchgit,
}:
writeShellApplication {
  name = "attos-ci";
  # nix comes from the job environment (the nixos/nix container).
  runtimeInputs = [
    coreutils
    findutils
    gnugrep
    gnused
    curl
    gitMinimal
    jq
    nix-update
    update-nix-fetchgit
  ];
  text = builtins.readFile ./attos-ci.sh;
}
