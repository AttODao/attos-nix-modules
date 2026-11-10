{
  writeShellApplication,
  coreutils,
  findutils,
  gawk,
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
    gawk
    gnugrep
    gnused
    curl
    gitMinimal
    jq
    nix-update
    update-nix-fetchgit
  ];
  # `attos-ci docs` evaluates this file against the checkout (option declarations → wiki tables).
  runtimeEnv.ATTOS_CI_OPTIONS_DOC = "${./options-doc.nix}";
  text = builtins.readFile ./attos-ci.sh;
}
