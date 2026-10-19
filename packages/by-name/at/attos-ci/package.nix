{
  writeShellApplication,
  attic-client,
  curl,
  gitMinimal,
  jq,
  nix-update,
  update-nix-fetchgit,
}:
writeShellApplication {
  name = "attos-ci";
  # nix comes from the runner host so builds use its daemon and substituters.
  runtimeInputs = [
    attic-client
    curl
    gitMinimal
    jq
    nix-update
    update-nix-fetchgit
  ];
  text = builtins.readFile ./attos-ci.sh;
}
