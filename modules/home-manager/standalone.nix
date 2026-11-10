# Standalone Home Manager entry point (flake.modules.homeManager.default).
#
# Users write the same `modules.<name>.*` settings as on NixOS. This module evaluates the
# NixOS-side feature modules (../default.nix) on their own with `lib.evalModules`: a lazy
# freeform root absorbs the NixOS options they set (services, systemd, fonts, ...) without
# NixOS, and the result is passed to every feature home.nix as `osConfig`, exactly as the
# integrated NixOS + Home Manager setup does.
#
# Every feature home.nix is imported statically (imports must not depend on config); each one
# is guarded by `osConfig.modules.<name>.enable`, so disabled features add nothing.
# Features whose home.nix reads NixOS-only options cannot be enabled here: hyprland
# (programs.hyprland) and attos-mouse (programs.uwsm), and features that enable them; see README.
{ attopkgsFor }:
{
  lib,
  options,
  pkgs,
  ...
}:
let
  modulesDir = ../.;
  # Same order as the NixOS side imports the features (modules/default.nix).
  homeFiles = builtins.filter builtins.pathExists (
    map (dir: dir + "/home.nix") (import modulesDir).imports
  );

  # Like `types.anything`, but attribute sets merge lazily at every level, so reading one
  # NixOS option (e.g. `osConfig.services.foo`) never forces the conditions of its siblings.
  # A set whose definitions are all disabled (`mkIf false`) reads as `{ }`.
  lazyAnything = lib.mkOptionType {
    name = "lazyAnything";
    description = "NixOS-side value absorbed for standalone Home Manager";
    merge =
      loc: defs:
      if lib.all (def: builtins.isAttrs def.value && !lib.isStringLike def.value) defs then
        (lib.types.lazyAttrsOf lazyAnything).merge loc defs
      else
        lib.types.anything.merge loc defs;
    emptyValue.value = { };
  };

  attopkgs = attopkgsFor pkgs;
  ps = import ../public-services/lib.nix { inherit lib; };

  # The Home Manager definitions of `modules`, with priorities (mkDefault, mkForce) and
  # conditions below the top level kept, become definitions of the inner evaluation.
  settings = options.modules.definitionsWithLocations;

  inner = lib.evalModules {
    class = "nixos";
    # Module arguments come from specialArgs: with a freeform root, reading `_module.args` needs
    # every module evaluated first, so arguments from there would recurse.
    specialArgs = { inherit pkgs attopkgs ps; };
    modules = [
      {
        freeformType = lib.types.lazyAttrsOf lazyAnything;
        options = {
          home-manager.sharedModules = lib.mkOption {
            type = lib.types.listOf lib.types.raw;
            default = [ ];
            description = "Home Manager modules the features would add on NixOS (imported statically here).";
          };
          assertions = lib.mkOption {
            type = lib.types.listOf lib.types.unspecified;
            default = [ ];
            description = "NixOS-side assertions, forwarded to Home Manager.";
          };
          warnings = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
            description = "NixOS-side warnings, forwarded to Home Manager.";
          };
        };
      }
      modulesDir
    ]
    ++ map (def: {
      _file = def.file;
      config.modules = def.value;
    }) settings;
  };

  # Paths under `modules` that no shared option declares (the freeform root would absorb them).
  unknownPaths =
    prefix: value: opts:
    lib.concatLists (
      lib.mapAttrsToList (
        name: v:
        let
          path = prefix ++ [ name ];
        in
        if !(opts ? ${name}) then
          [ path ]
        else if lib.isOption opts.${name} then
          [ ]
        else if builtins.isAttrs v && !(v ? _type) then
          unknownPaths path v opts.${name}
        else
          [ ]
      ) value
    );
  unknown = lib.concatMap (
    def:
    map (path: {
      inherit (def) file;
      inherit path;
    }) (if builtins.isAttrs def.value then unknownPaths [ ] def.value inner.options.modules else [ ])
  ) settings;
in
{
  key = "attos-nix-modules#homeManager.default";

  imports = homeFiles;

  options.modules = lib.mkOption {
    type = lib.mkOptionType {
      name = "attosModules";
      description = "attos-nix-modules settings (modules.<name>.*)";
      check = builtins.isAttrs;
      merge = _loc: defs: defs;
    };
    default = { };
    # Reads back the merged settings, including values the features set for each other.
    apply = _: inner.config.modules;
    description = ''
      Settings of the shared feature modules, written as on NixOS (`modules.<name>.enable` etc.).
      Set priorities on the leaves (`modules.foo.enable = lib.mkForce false;`), not on `modules` itself.
    '';
  };

  config = {
    _module.args = {
      osConfig = inner.config;
      inherit attopkgs ps;
    };

    assertions =
      inner.config.assertions
      ++ map (u: {
        assertion = false;
        message = "${u.file}: modules.${lib.showOption u.path} is not an option of attos-nix-modules.";
      }) unknown;
    warnings = inner.config.warnings;
  };
}
