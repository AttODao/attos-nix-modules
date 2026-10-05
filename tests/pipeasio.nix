# nix-instantiate --eval --strict tests/pipeasio.nix \
#   --arg nixpkgs /path/to/nixpkgs --arg homeManager /path/to/home-manager
{
  nixpkgs,
  homeManager,
  system ? builtins.currentSystem,
}:
let
  t = import ./lib.nix {
    inherit nixpkgs homeManager system;
    nixpkgsConfig.allowUnfree = true;
  };
  inherit (t) lib;
  base = t.cfgFor [ { hardware.graphics.enable = true; } ];
  enabledCfg = t.cfgFor [
    {
      modules.pipeasio.enable = true;
      hardware.graphics.enable = true;
    }
  ];
  enabled = t.hm enabledCfg "test";
  steamEvaluation = t.eval [
    {
      modules.pipeasio.enable = true;
      hardware.graphics.enable = true;
      programs.steam.enable = true;
    }
  ];
  steamEnabled = steamEvaluation.config;
  invalid =
    builtins.tryEval
      (t.cfgFor [ { modules.pipeasio.enable = "yes"; } ]).modules.pipeasio.enable;
  registration = lib.findFirst (
    p: p.name == "pipeasio-register-steam-prefixes"
  ) null enabled.home.packages;
in
assert !base.modules.pipeasio.enable;
assert builtins.elem t.attopkgs.pipeasio enabled.home.packages;
assert registration != null;
assert !(lib.hasInfix "@PYTHON@" registration.text);
assert lib.hasInfix
  (builtins.unsafeDiscardStringContext "${t.attopkgs.pipeasio}/bin/pipeasio-manage")
  registration.text;
assert lib.hasInfix
  (builtins.unsafeDiscardStringContext "${t.attopkgs.pipeasio}/bin/pipeasio-register")
  registration.text;
assert enabled.home.activation.registerPipeasioSteamPrefixes.after == [ "writeBoundary" ];
assert lib.hasInfix "--skip-registered --no-runtime-download"
  enabled.home.activation.registerPipeasioSteamPrefixes.data;
assert lib.hasSuffix ".drv" enabled.home.activationPackage.drvPath;
assert builtins.elem t.attopkgs.pipeasio enabledCfg.environment.systemPackages;
assert !enabledCfg.programs.steam.enable;
assert enabledCfg.programs.steam.package.drvPath == base.programs.steam.package.drvPath;
assert
  steamEnabled.programs.steam.package.drvPath == (steamEvaluation.options.programs.steam.package.apply
    (
      steamEvaluation.pkgs.steam.override {
        extraEnv.WINEDLLPATH = "${t.attopkgs.pipeasio}/lib/wine";
      }
    )
  ).drvPath;
assert t.attopkgs.pipeasio.version == "1.10.0";
assert !invalid.success;
true
