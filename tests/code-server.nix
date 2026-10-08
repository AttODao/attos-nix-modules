{
  nixpkgs,
  homeManager,
  system ? builtins.currentSystem,
}:
let
  t = import ./lib.nix { inherit nixpkgs homeManager system; };
  inherit (t) lib;
  endpoint.modules.public-services."code.example.test".code-server = {
    enable = true;
    host = "development";
    backendUrl = "http://10.0.0.4:4444";
  };
  base = t.cfgFor [ ];
  remote = t.cfgFor [ endpoint ];
  local = t.cfgFor [
    endpoint
    {
      networking.hostName = "development";
      modules.public-services."code.example.test".code-server = {
        environmentFile = "/run/secrets/code-server.env";
        user = "test";
        group = "users";
      };
      services.code-server = {
        userDataDir = "/srv/code/data";
        extensionsDir = "/srv/code/extensions";
      };
    }
  ];
  registrationOnly = t.cfgFor [
    endpoint
    {
      networking.hostName = "development";
      modules.public-services."code.example.test".code-server = {
        deploy = false;
        packageSource = "/does-not-exist/code-server-release";
      };
      _module.args.attopkgs = lib.mkForce (
        t.attopkgs
        // {
          code-server = _: throw "Endpoint-only source must not be evaluated";
        }
      );
    }
  ];
  overridden = t.cfgFor [
    endpoint
    {
      networking.hostName = "development";
      services.code-server = {
        auth = "none";
        host = "127.0.0.1";
        port = 5555;
        disableTelemetry = false;
        package = t.pkgs.writeShellScriptBin "code-server" "exit 0";
      };
    }
  ];
  sourcePackage = t.pkgs.writeShellScriptBin "code-server" "exit 0";
  sourced = t.cfgFor [
    endpoint
    {
      networking.hostName = "development";
      modules.public-services."code.example.test".code-server = {
        environmentFile = "/home/test/code-server/server.env";
        packageSource = nixpkgs;
        user = "test";
        group = "users";
      };
      _module.args.attopkgs = lib.mkForce (
        t.attopkgs
        // {
          code-server =
            { src }:
            assert toString src == toString nixpkgs;
            sourcePackage;
        }
      );
    }
  ];
  isolated = t.cfgFor [
    endpoint
    {
      modules.public-services."code.example.test".code-server.packageSource =
        "/does-not-exist/code-server-release";
      _module.args.attopkgs = lib.mkForce (
        t.attopkgs
        // {
          code-server = _: throw "Remote source must not be evaluated";
        }
      );
    }
  ];
  invalidUser =
    builtins.tryEval
      (t.cfgFor [
        { modules.public-services."code.example.test".code-server.user = ""; }
      ]).modules.public-services."code.example.test".code-server.user;
  invalidSource =
    builtins.tryEval
      (t.cfgFor [
        { modules.public-services."code.example.test".code-server.packageSource = 42; }
      ]).modules.public-services."code.example.test".code-server.packageSource;
  missing =
    builtins.tryEval
      (t.cfgFor [
        endpoint
        {
          networking.hostName = "development";
        }
      ]).systemd.services.code-server.serviceConfig.EnvironmentFile;
  invalid =
    builtins.tryEval
      (t.cfgFor [
        endpoint
        {
          modules.public-services."code.example.test".code-server.environmentFile = /tmp/credential;
        }
      ]).modules.public-services."code.example.test".code-server.environmentFile;
in
assert !base.services.code-server.enable && !remote.services.code-server.enable;
assert !(remote.systemd.services ? code-server);
assert !registrationOnly.services.code-server.enable;
assert !(registrationOnly.systemd.services ? code-server);
assert local.modules.public-services."code.example.test".code-server.deploy;
assert local.services.code-server.enable;
assert local.services.code-server.package == t.pkgs.code-server;
assert local.services.code-server.user == "test" && local.services.code-server.group == "users";
assert sourced.services.code-server.package == sourcePackage;
assert sourced.services.code-server.extraEnvironment.HOME == "/home/test";
assert sourced.systemd.services.code-server.serviceConfig.User == "test";
assert sourced.systemd.services.code-server.serviceConfig.Group == "users";
assert isolated.services.code-server.package == t.pkgs.code-server;
assert !isolated.services.code-server.enable;
assert !invalidUser.success && !invalidSource.success;
assert local.services.code-server.auth == "password";
assert local.services.code-server.disableTelemetry && local.services.code-server.disableUpdateCheck;
assert local.services.code-server.extraEnvironment.HOME == "/home/test";
assert
  local.systemd.services.code-server.serviceConfig.EnvironmentFile == "/run/secrets/code-server.env";
assert local.systemd.services.code-server.serviceConfig.UMask == "0077";
assert lib.elem "/srv/code/data" local.systemd.services.code-server.unitConfig.RequiresMountsFor;
assert overridden.services.code-server.enable;
assert overridden.services.code-server.host == "127.0.0.1";
assert overridden.services.code-server.port == 5555;
assert !overridden.services.code-server.disableTelemetry;
assert !missing.success && !invalid.success;
assert !base.modules.code-server.enable;
assert lib.all (a: a.assertion) local.assertions;
true
