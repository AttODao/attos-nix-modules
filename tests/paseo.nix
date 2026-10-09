# nix-instantiate --eval --strict tests/paseo.nix \
#   --arg nixpkgs /path/to/nixpkgs --arg homeManager /path/to/home-manager
{
  nixpkgs,
  homeManager,
  system ? builtins.currentSystem,
}:
let
  t = import ./lib.nix {
    inherit nixpkgs homeManager system;
    nixpkgsConfig.allowUnfreePredicate =
      pkg: (import "${toString nixpkgs}/lib").getName pkg == "context-mode";
  };
  inherit (t) pkgs lib;
  base =
    t.hm
      (t.evalSystem {
        users = [ "dev" ];
        modules = [ { users.users.dev.home = "/srv/dev"; } ];
      }).config
      "dev";
  enabled =
    t.hm
      (t.evalSystem {
        users = [ "dev" ];
        modules = [
          { users.users.dev.home = "/srv/dev"; }
          {
            modules.paseo = {
              enable = true;
              hostname = "devcon.attodao.cc";
            };
            home-manager.users.dev.programs.pi-coding-agent.configDir = "/srv/dev/custom-pi";
          }
        ];
      }).config
      "dev";
  service = enabled.systemd.user.services.paseo-daemon;
  invalid =
    option: value:
    builtins.tryEval (t.cfgFor [ { modules.paseo.${option} = value; } ]).modules.paseo.${option};
  standalone = t.cfgFor [ { modules.paseo.enable = true; } ];
in
assert !base.programs.pi-coding-agent.enable;
assert enabled.programs.pi-coding-agent.enable;
assert enabled.programs.pi-coding-agent.package.version == "1.0.2";
assert enabled.home.file."/srv/dev/custom-pi/settings.json".enable;
assert enabled.home.file."/srv/dev/custom-pi/extensions/ponytail".enable;
assert service.Service.WorkingDirectory == "/srv/dev";
assert builtins.elem "HOME=/srv/dev" service.Service.Environment;
assert builtins.elem "PASEO_HOME=/srv/dev/paseo" service.Service.Environment;
assert builtins.elem "PI_CODING_AGENT_DIR=/srv/dev/custom-pi" service.Service.Environment;
assert builtins.elem "NPM_CONFIG_CACHE=/srv/dev/paseo/npm-cache" service.Service.Environment;
assert builtins.any (lib.hasPrefix "PATH=${enabled.home.path}/bin:") service.Service.Environment;
assert service.Service.EnvironmentFile == "/srv/dev/paseo/daemon.env";
assert service.Unit.ConditionPathExists == "/srv/dev/paseo/daemon.env";
assert service.Install.WantedBy == [ "default.target" ];
assert !(service.Service ? User);
assert service.Service.UMask == "0077";
assert lib.hasInfix "install -d -m 0700 ${lib.escapeShellArg "/srv/dev/paseo"}"
  service.Service.ExecStartPre.text;
assert lib.hasInfix "paseo-config.json" service.Service.ExecStartPre.text;
assert lib.hasSuffix " daemon run --home ${lib.escapeShellArg "/srv/dev/paseo"}" (
  builtins.head service.Service.ExecStart
);
assert builtins.elem t.attopkgs.paseo enabled.home.packages;
assert t.attopkgs.paseo.version == "0.11.1";
assert lib.hasPrefix "${t.attopkgs.paseo}/bin/paseo " (builtins.head service.Service.ExecStart);
assert !lib.hasInfix "npx" (builtins.head service.Service.ExecStart);
assert !lib.hasInfix "@latest" (builtins.readFile ../modules/paseo/home.nix);
assert !(invalid "enable" "yes").success;
assert !(invalid "hostname" "").success;
assert standalone.modules.paseo.hostname == "localhost";
true
