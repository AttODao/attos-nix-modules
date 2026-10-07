# nix-instantiate --eval --strict tests/atcoder.nix \
#   --arg nixpkgs /path/to/nixpkgs --arg homeManager /path/to/home-manager
{
  nixpkgs,
  homeManager,
  system ? builtins.currentSystem,
}:
let
  t = import ./lib.nix { inherit nixpkgs homeManager system; };
  inherit (t) pkgs lib;

  dummy = name: pkgs.runCommand name { } "mkdir -p $out/bin; touch $out/bin/${name}";
  attopkgs = t.attopkgs // rec {
    atcoder-cli = dummy "acc";
    atcoder-oj = dummy "oj";
    atcoder-aclogin = dummy "aclogin";
    atcoder-commands =
      args:
      pkgs.callPackage ../packages/atcoder-commands.nix (
        args // { aclogin = args.aclogin or atcoder-aclogin; }
      );
  };
  atcoderModule = {
    imports = [ ../modules/atcoder ];
    _module.args.attopkgs = lib.mkForce attopkgs;
  };

  cfg = modules: t.cfgFor ([ atcoderModule ] ++ modules);
  actual = t.hmFor [ { modules.atcoder.enable = true; } ];
  base = cfg [ ];
  enabledCfg = cfg [ { modules.atcoder.enable = true; } ];
  enabled = t.hm enabledCfg "test";
  commands = lib.findFirst (p: (p.passthru.commands or [ ]) != [ ]) null enabled.home.packages;

  multiCfg = t.evalSystem {
    users = [
      "alice"
      "bob"
    ];
    modules = [
      atcoderModule
      { modules.atcoder.enable = true; }
      { users.users.bob.home = "/srv/bob"; }
    ];
  };
  alice = t.hm multiCfg.config "alice";
  bob = t.hm multiCfg.config "bob";

  overrideCfg = cfg [
    { modules.atcoder.enable = true; }
    { home-manager.users.test.programs.go.package = pkgs.go; }
  ];
  override = t.hm overrideCfg "test";
in
assert !base.modules.atcoder.enable;
assert !base.modules.zsh.enable;
assert !base.home-manager.users.test.programs.go.enable;
assert !base.home-manager.users.test.programs.direnv.enable;
assert enabledCfg.modules.zsh.enable;
assert enabled.programs.go.enable;
assert enabled.programs.go.package == pkgs.go;
assert enabled.programs.direnv.enable;
assert enabled.programs.direnv.enableZshIntegration;
assert enabled.home.sessionVariables.GOTOOLCHAIN == "local";
assert builtins.elem attopkgs.atcoder-cli enabled.home.packages;
assert builtins.elem attopkgs.atcoder-oj enabled.home.packages;
assert builtins.elem attopkgs.atcoder-aclogin enabled.home.packages;
assert commands != null;
assert
  commands.passthru.commands == [
    "atcoder-go"
    "atcoder-init"
    "atcoder-sync"
    "go-run"
    "acc-login"
  ];
assert alice.home.homeDirectory == "/home/alice";
assert bob.home.homeDirectory == "/srv/bob";
assert (lib.findFirst (p: (p.passthru.commands or [ ]) != [ ]) null alice.home.packages) != null;
assert (lib.findFirst (p: (p.passthru.commands or [ ]) != [ ]) null bob.home.packages) != null;
assert override.programs.go.package == pkgs.go;
assert lib.hasSuffix ".drv" enabled.home.activationPackage.drvPath;
assert lib.elem t.attopkgs.atcoder-cli actual.home.packages;
assert lib.elem t.attopkgs.atcoder-oj actual.home.packages;
assert lib.elem t.attopkgs.atcoder-aclogin actual.home.packages;
assert lib.hasSuffix ".drv" actual.home.activationPackage.drvPath;
true
