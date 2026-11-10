# attos-ci docs: the modules.* option declarations of nixosModules.default as JSON.
# Evaluated with a minimal nixosSystem so that types and defaults render; nothing is built.
# Usage: nix eval --impure --json --expr 'import ./options-doc.nix { flakeRef = "path:<checkout>"; }'
{ flakeRef }:
let
  flake = builtins.getFlake flakeRef;
  inherit (flake.inputs.nixpkgs) lib;
  nixos = lib.nixosSystem {
    modules = [
      flake.nixosModules.default
      {
        nixpkgs.hostPlatform = "x86_64-linux";
        boot.isContainer = true;
        system.stateVersion = lib.trivial.release;
      }
    ];
  };
  # A default that cannot be rendered with the minimal system (it reads other config) becomes a note.
  render =
    v:
    let
      r = builtins.tryEval (
        if v == null then
          null
        else if builtins.isAttrs v && v ? text then
          builtins.deepSeq v.text v.text
        else
          builtins.deepSeq v (builtins.toJSON v)
      );
    in
    if r.success then r.value else "（評価できません）";
  modulesDir = toString flake.outPath + "/modules/";
  # modules/<dir>/... of each declaration (relative to the checkout).
  dirOf' =
    decl:
    let
      s = toString decl;
      rel = lib.removePrefix modulesDir s;
    in
    if rel != s then builtins.head (lib.splitString "/" rel) else null;
in
map (o: {
  inherit (o) name loc;
  type = o.type or null;
  default = if o ? default then render o.default else null;
  description = o.description or null;
  readOnly = o.readOnly or false;
  dirs = lib.unique (lib.filter (d: d != null) (map dirOf' o.declarations));
  declarations = map toString o.declarations;
}) (lib.filter (o: o.visible && !o.internal) (lib.optionAttrSetToDocList nixos.options.modules))
