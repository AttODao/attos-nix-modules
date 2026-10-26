# nixpkgsのpkgs/by-nameと同じく、by-name/<shard>/<name>/package.nixを自動登録する。
{ pkgs, inputs }:
let
  inherit (pkgs) lib;
  dirs = path: lib.attrNames (lib.filterAttrs (_: type: type == "directory") (builtins.readDir path));
  byName = lib.concatMap (
    shard:
    map (
      name:
      let
        file = ./by-name/${shard}/${name}/package.nix;
      in
      if !builtins.pathExists file then
        throw "packages/by-name/${shard}/${name}: package.nix is missing."
      else if shard != builtins.substring 0 2 name then
        throw "packages/by-name/${shard}/${name}: the shard must be the first two characters of the package name."
      else
        lib.nameValuePair name file
    ) (dirs ./by-name/${shard})
  ) (dirs ./by-name);
  # root直下にpackage.nixを持つ外部source input（flake = false）。version・revisionはflake.nix / flake.lockだけが持つ。
  lock = lib.importJSON ../flake.lock;
  lockedInput = name: lock.nodes.${lock.nodes.${lock.root}.inputs.${name}};
  external = self: {
    claude-code = self.callPackage "${inputs.claude-code-nix}/package.nix" { };
    # flake inputのsource（outPath・rev・lastModified）と、flake.nixのrelease tag（lockのoriginal.ref）から取ったversion。
    hermes-agent-src = inputs.hermes-agent // {
      version = lib.removePrefix "v" (lockedInput "hermes-agent").original.ref;
    };
  };
  collisions = lib.intersectLists (map (entry: entry.name) byName) (lib.attrNames (external null));
in
if collisions != [ ] then
  throw "packages: ${lib.concatStringsSep ", " collisions} defined both under by-name and in the external input table."
else
  lib.makeScope pkgs.newScope (
    self: lib.mapAttrs (_: file: self.callPackage file { }) (lib.listToAttrs byName) // external self
  )
