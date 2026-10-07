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
  endpoint.modules.public-services."sun.example.test".sunshine = {
    enable = true;
    host = "desktop";
    backendUrl = "https://10.0.0.5:47990";
  };
  base = t.cfgFor [ ];
  remote = t.cfgFor [ endpoint ];
  local = t.cfgFor [
    endpoint
    { networking.hostName = "desktop"; }
  ];
  registrationOnly = t.cfgFor [
    endpoint
    {
      networking.hostName = "desktop";
      modules.public-services."sun.example.test".sunshine.deploy = false;
    }
  ];
  disabled = t.cfgFor [
    {
      networking.hostName = "desktop";
      modules.public-services."sun.example.test".sunshine = {
        enable = false;
        host = "desktop";
        backendUrl = "https://10.0.0.5:47990";
      };
    }
  ];
  overridden = t.cfgFor [
    endpoint
    {
      networking.hostName = "desktop";
      services.sunshine = {
        settings = {
          capture = "kms";
          audio_sink = "consumer-sink";
          output_name = "consumer-output";
        };
        applications.apps = [ { name = "Consumer App"; } ];
        autoStart = false;
      };
    }
  ];
  oldAlias =
    builtins.tryEval
      (t.cfgFor [ { modules.sunshine.enable = true; } ]).modules.sunshine.enable;
in
assert !base.services.sunshine.enable && !remote.services.sunshine.enable;
assert !remote.modules.hyprland.enable && !remote.modules.steam.enable;
assert !(remote.systemd.user.services ? sunshine);
assert !registrationOnly.services.sunshine.enable;
assert !registrationOnly.modules.hyprland.enable && !registrationOnly.modules.steam.enable;
assert !disabled.services.sunshine.enable;
assert !disabled.modules.hyprland.enable && !disabled.modules.steam.enable;
assert local.modules.public-services."sun.example.test".sunshine.deploy;
assert
  local.services.sunshine.enable && local.modules.hyprland.enable && local.modules.steam.enable;
assert !local.services.sunshine.openFirewall && !local.services.sunshine.capSysAdmin;
assert local.services.sunshine.settings.sunshine_name == "desktop";
assert local.services.sunshine.settings.csrf_allowed_origins == "https://sun.example.test";
assert local.services.sunshine.settings.capture == "wlr";
assert
  map (app: app.name) local.services.sunshine.applications.apps == [
    "Desktop"
    "Steam Big Picture"
  ];
assert !(local.services.sunshine.settings ? audio_sink);
assert !(local.systemd.user.services ? hyprland-headless-output);
assert overridden.services.sunshine.enable;
assert overridden.services.sunshine.settings.capture == "kms";
assert overridden.services.sunshine.settings.audio_sink == "consumer-sink";
assert overridden.services.sunshine.applications.apps == [ { name = "Consumer App"; } ];
assert !overridden.services.sunshine.autoStart;
assert !oldAlias.success;
assert lib.all (a: a.assertion) local.assertions;
true
