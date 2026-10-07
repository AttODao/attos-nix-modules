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
      modules.public-services."code.example.test".code-server.environmentFile =
        "/run/secrets/code-server.env";
      services.code-server = {
        user = "test";
        group = "users";
        userDataDir = "/srv/code/data";
        extensionsDir = "/srv/code/extensions";
      };
    }
  ];
  registrationOnly = t.cfgFor [
    endpoint
    {
      networking.hostName = "development";
      modules.public-services."code.example.test".code-server.deploy = false;
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
  oldAlias =
    builtins.tryEval
      (t.cfgFor [ { modules.code-server.enable = true; } ]).modules.code-server.enable;
in
assert !base.services.code-server.enable && !remote.services.code-server.enable;
assert !(remote.systemd.services ? code-server);
assert !registrationOnly.services.code-server.enable;
assert !(registrationOnly.systemd.services ? code-server);
assert local.modules.public-services."code.example.test".code-server.deploy;
assert local.services.code-server.enable;
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
assert !missing.success && !invalid.success && !oldAlias.success;
assert lib.all (a: a.assertion) local.assertions;
true
