# nixpkgsのpkgs/by-nameと同じく、by-name/<shard>/<name>/package.nixを自動登録する。
{ pkgs, inputs }:
let
  inherit (pkgs) lib;
  dirs = path: lib.attrNames (lib.filterAttrs (_: type: type == "directory") (builtins.readDir path));
  byName = lib.concatMap (
    shard:
    map (name: lib.nameValuePair name ./by-name/${shard}/${name}/package.nix) (dirs ./by-name/${shard})
  ) (dirs ./by-name);
in
lib.makeScope pkgs.newScope (
  self:
  lib.mapAttrs (_: file: self.callPackage file { }) (lib.listToAttrs byName)
  # root直下にpackage.nixを持つ外部source input（flake = false）。
  // {
    claude-code = self.callPackage "${inputs.claude-code-nix}/package.nix" { };
  }
)
