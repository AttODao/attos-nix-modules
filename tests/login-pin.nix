# nix-instantiate --eval --strict tests/login-pin.nix \
#   --arg nixpkgs /path/to/nixpkgs --arg homeManager /path/to/home-manager
{
  nixpkgs,
  homeManager,
  system ? builtins.currentSystem,
}:
let
  t = import ./lib.nix { inherit nixpkgs homeManager system; };
  inherit (t) lib;
  base = t.cfgFor [ ];
  enabled = t.cfgFor [
    {
      modules.login-pin.enable = true;
      services.openssh.enable = true;
      services.greetd.enable = true;
      services.greetd.settings.default_session.command = "agreety";
    }
  ];
  withSecret = t.cfgFor [
    {
      options.sops.secrets = lib.mkOption {
        type = lib.types.attrs;
        default = { };
      };
      config = {
        modules.login-pin.enable = true;
        sops.secrets."login-pin/attodao.pbkdf2".path = "/run/secrets/login-pin/attodao.pbkdf2";
      };
    }
  ];
  invalidType =
    builtins.tryEval
      (t.cfgFor [ { modules.login-pin.enable = "yes"; } ]).modules.login-pin.enable;
  checkPath = config: builtins.elemAt config.security.pam.services.login.rules.auth.login-pin.args 2;
in
assert !base.modules.login-pin.enable;
assert !(base.security.pam.services.login.rules.auth ? login-pin);
assert enabled.system.activationScripts ? loginPinDir;
assert builtins.any (p: p.name == "set-login-pin") enabled.environment.systemPackages;
assert !(withSecret.system.activationScripts ? loginPinDir);
assert !(builtins.any (p: p.name == "set-login-pin") withSecret.environment.systemPackages);
assert checkPath enabled != checkPath withSecret;
assert lib.all
  (
    name:
    let
      service = enabled.security.pam.services.${name};
    in
    service.unixAuth
    && service.rules.auth.login-pin.control == "sufficient"
    &&
      service.rules.auth.login-pin.args == [
        "quiet"
        "expose_authtok"
        (checkPath enabled)
      ]
    &&
      service.rules.auth.login-pin.order
      < service.rules.auth.${if name == "greetd" then "login" else "unix"}.order
  )
  [
    "greetd"
    "login"
  ];
assert !(enabled.security.pam.services.sshd.rules.auth ? login-pin);
assert !invalidType.success;
true
