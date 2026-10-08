{
  nixpkgs,
  homeManager,
  isolationNixpkgs ? nixpkgs,
  system ? builtins.currentSystem,
}:
let
  t = import ./lib.nix {
    inherit nixpkgs homeManager system;
    nixpkgsConfig.allowUnfree = true;
  };
  inherit (t) lib;
  isolationTools = import ./lib.nix {
    nixpkgs = isolationNixpkgs;
    inherit homeManager system;
  };
  disabledDesktop = isolationTools.cfgFor [
    {
      # Match the development guest's existing compatibility imports, not a pin upgrade.
      disabledModules = [
        "programs/solaar.nix"
        "services/display-managers/noctalia-greeter.nix"
      ];
      imports = [
        "${nixpkgs}/nixos/modules/programs/solaar.nix"
        "${nixpkgs}/nixos/modules/services/display-managers/noctalia-greeter.nix"
      ];
      networking.hostName = "development";
      modules.hyprland.headless.enable = true;
      modules.noctalia = {
        package = t.pkgs.noctalia;
        systemd = {
          enable = true;
          requires = [ "unused.service" ];
          after = [ "unused.service" ];
        };
      };
      modules.pipewire.virtualSinks.sunshine = {
        name = "unused";
        description = "Unused";
      };
      modules.public-services."remote.example.test".sunshine = inputs // {
        enable = true;
        host = "desktop";
        backendUrl = "https://10.0.0.5:47990";
      };
    }
  ];
  endpoint.modules.public-services."sun.example.test".sunshine = {
    enable = true;
    host = "desktop";
    backendUrl = "https://10.0.0.5:47990";
  };
  base = t.cfgFor [ ];
  apps = [
    {
      name = "Desktop";
      image-path = "desktop.png";
    }
    {
      name = "Low Res Desktop";
      image-path = "desktop.png";
      prep-cmd = [
        {
          do = "hyprctl keyword monitor moonlight,1920x1080@60,auto,1";
          undo = "hyprctl keyword monitor moonlight,1920x1200@60,auto,1";
        }
      ];
    }
    {
      name = "Steam Big Picture";
      detached = [ "setsid steam steam://open/bigpicture" ];
      prep-cmd = [
        {
          do = "";
          undo = "setsid steam steam://close/bigpicture";
        }
      ];
      image-path = "steam.png";
    }
  ];
  inputs = {
    settings = {
      audio_sink = "sink-sunshine-stereo";
      output_name = "moonlight";
      capture = "kms";
    };
    inherit apps;
    waitForHeadlessOutput = true;
  };
  desktop = t.cfgFor [
    endpoint
    {
      networking.hostName = "desktop";
      modules.hyprland.headless.enable = true;
      modules.pipewire = {
        enable = true;
        virtualSinks.sunshine = {
          name = "sink-sunshine-stereo";
          description = "Sunshine Stereo";
        };
      };
      modules.public-services."sun.example.test".sunshine = inputs;
    }
  ];
  manualDesktop = t.cfgFor [
    endpoint
    {
      networking.hostName = "desktop";
      modules.hyprland.headless.enable = true;
      modules.public-services."sun.example.test".sunshine = inputs;
      services.sunshine.autoStart = false;
    }
  ];
  isolated = t.cfgFor [
    endpoint
    {
      modules.public-services."sun.example.test".sunshine = inputs;
      modules.pipewire.virtualSinks.sunshine = {
        name = "unused";
        description = "Unused";
      };
    }
  ];
  endpointInputs = t.cfgFor [
    endpoint
    {
      networking.hostName = "desktop";
      modules.public-services."sun.example.test".sunshine = inputs // {
        deploy = false;
      };
    }
  ];
  invalidWait = t.cfgFor [
    endpoint
    {
      networking.hostName = "desktop";
      modules.public-services."sun.example.test".sunshine.waitForHeadlessOutput = true;
    }
  ];
  invalid =
    value:
    builtins.tryEval (
      builtins.deepSeq
        (t.cfgFor [ { modules.public-services."sun.example.test".sunshine = value; } ])
        .modules.public-services
        true
    );
  invalidSink = builtins.tryEval (
    builtins.deepSeq
      (t.cfgFor [
        {
          modules.pipewire.virtualSinks.test = {
            name = "";
            description = "Test";
          };
        }
      ]).modules.pipewire
      true
  );
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
assert !disabledDesktop.services.sunshine.enable;
assert !disabledDesktop.services.seatd.enable;
assert !(disabledDesktop.systemd.services ? container-udevd);
assert !(disabledDesktop.systemd.user.services ? hyprland-bootstrap);
assert !(disabledDesktop.systemd.user.services ? hyprland-headless-output);
assert !(disabledDesktop.systemd.user.services ? sunshine);
assert !(disabledDesktop.services.pipewire.extraConfig.pipewire ? "99-sunshine-sink");
assert !(disabledDesktop.home-manager.users.test.systemd.user.services ? noctalia);
assert !disabledDesktop.home-manager.users.test.programs.noctalia.enable;
assert lib.all (a: a.assertion) disabledDesktop.assertions;
assert desktop.services.sunshine.settings.audio_sink == "sink-sunshine-stereo";
assert desktop.services.sunshine.settings.output_name == "moonlight";
assert desktop.services.sunshine.settings.capture == "kms";
assert desktop.services.sunshine.applications.apps == apps;
assert manualDesktop.systemd.user.services.hyprland-headless-output.wants == [ ];
assert !(local.systemd.user.services ? hyprland-headless-output);
assert desktop.systemd.user.services.hyprland-headless-output.wants == [ "sunshine.service" ];
assert desktop.systemd.user.services.sunshine.requires == [ "hyprland-headless-output.service" ];
assert lib.elem "hyprland-headless-output.service" desktop.systemd.user.services.sunshine.after;
assert
  desktop.services.pipewire.extraConfig.pipewire."99-sunshine-sink"."context.objects" == [
    {
      factory = "adapter";
      args = {
        "factory.name" = "support.null-audio-sink";
        "node.name" = "sink-sunshine-stereo";
        "node.description" = "Sunshine Stereo";
        "media.class" = "Audio/Sink";
        "object.linger" = true;
        "audio.position" = [
          "FL"
          "FR"
        ];
      };
    }
  ];
assert lib.all (a: a.assertion) desktop.assertions;
assert desktop.system.build.toplevel.drvPath != "";
assert !(isolated.systemd.user.services ? sunshine);
assert !(isolated.systemd.user.services ? hyprland-headless-output);
assert !(isolated.services.pipewire.extraConfig.pipewire ? "99-sunshine-sink");
assert !(endpointInputs.systemd.user.services ? sunshine);
assert !endpointInputs.modules.hyprland.enable;
assert lib.any (
  a: !a.assertion && lib.hasInfix "waitForHeadlessOutput requires" a.message
) invalidWait.assertions;
assert !(invalid { settings.capture = [ "kms" ]; }).success;
assert !(invalid { apps = [ { name = ""; } ]; }).success;
assert
  !(invalid {
    apps = [
      {
        name = "Bad";
        unexpected = true;
      }
    ];
  }).success;
assert
  !(invalid {
    apps = [
      {
        name = "Bad";
        prep-cmd = [ { do = 1; } ];
      }
    ];
  }).success;
assert !invalidSink.success;
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
