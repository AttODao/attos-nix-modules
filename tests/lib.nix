{
  nixpkgs,
  homeManager,
  system ? builtins.currentSystem,
  nixpkgsConfig ? { },
}:
let
  pkgs = import nixpkgs {
    inherit system;
    config = nixpkgsConfig;
  };
  inherit (pkgs) lib;
  # flake外の評価でも、未指定inputはflake.lockの固定revisionを使う。
  lock = builtins.fromJSON (builtins.readFile ../flake.lock);
  locked = name: builtins.fetchTree lock.nodes.${lock.nodes.root.inputs.${name}}.locked;
  exports = (import ../flake.nix).outputs {
    nixpkgs = {
      outPath = toString nixpkgs;
      inherit lib;
    };
    home-manager = homeManager;
    claude-code-nix = locked "claude-code-nix";
  };

  usersModule = users: {
    modules.home-manager.users = users;
    users.users = lib.genAttrs users (name: {
      isNormalUser = true;
      home = lib.mkDefault "/home/${name}";
    });
  };

  baseModule = {
    system.stateVersion = "26.05";
    boot.isContainer = true;
    fileSystems."/" = {
      device = "none";
      fsType = "tmpfs";
    };
    nixpkgs.config = nixpkgsConfig;
  };

  evalSystem =
    {
      users ? [ "test" ],
      modules ? [ ],
      includeDefault ? true,
    }:
    import "${toString nixpkgs}/nixos/lib/eval-config.nix" {
      inherit system;
      modules = [
        baseModule
        (usersModule users)
      ]
      ++ lib.optional includeDefault exports.nixosModules.default
      ++ modules;
    };

  eval = modules: evalSystem { inherit modules; };
  cfgFor = modules: (eval modules).config;
  hm = cfg: name: cfg.home-manager.users.${name};
  hmFor = modules: hm (cfgFor modules) "test";
in
{
  inherit
    pkgs
    lib
    exports
    evalSystem
    eval
    cfgFor
    hm
    hmFor
    ;
  attopkgs = exports.attopkgs { inherit pkgs; };
}
