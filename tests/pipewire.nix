# nix-instantiate --eval --strict tests/pipewire.nix \
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
  enabled = t.cfgFor [ { modules.pipewire.enable = true; } ];
  source = "alsa_input.usb-KURO-CPC_KURO-CPC-4K1C1PTwA_33400041-02.analog-stereo";
  target = "alsa_output.usb-Focusrite_Scarlett_Solo_4th_Gen_S1M5P213B255F6-00.HiFi__Line1__sink";
  audio = {
    alsaDevices.scarlett-solo = {
      deviceName = "alsa_card.usb-Focusrite_Scarlett_Solo_4th_Gen_S1M5P213B255F6-00";
      disableBatch = true;
      disableMmap = true;
      periodNum = 8;
      periodSize = 256;
      headroom = 128;
    };
    loopbacks = [
      {
        description = "KURO Loopback";
        inherit source;
        capturePassive = true;
        virtualSource.name = "kuro_capture";
      }
      {
        name = "kuro_monitor";
        description = "KURO Monitor";
        inherit source target;
      }
    ];
  };
  configured = t.cfgFor [
    {
      modules.pipewire = audio // {
        enable = true;
      };
    }
  ];
  disabled = t.cfgFor [ { modules.pipewire = audio; } ];
  rules = cfg: key: cfg.services.pipewire.wireplumber.extraConfig."20-${key}"."monitor.alsa.rules";
  loopbacks = cfg: cfg.services.pipewire.extraConfig.pipewire."99-loopbacks"."context.modules";
  multiple = t.cfgFor [
    {
      modules.pipewire = {
        enable = true;
        alsaDevices = {
          first.deviceName = "arbitrary-first-card";
          second = {
            deviceName = "arbitrary-second-card";
            disableBatch = lib.mkDefault true;
            disableMmap = lib.mkDefault true;
            periodNum = lib.mkDefault 8;
            periodSize = lib.mkDefault 256;
            headroom = lib.mkDefault 128;
          };
        };
        loopbacks = [
          {
            name = "custom-loopback";
            description = "Custom source";
            source = "arbitrary-input";
            virtualSource = {
              name = "custom-source";
              channels = [ "MONO" ];
            };
          }
        ];
      };
    }
    {
      modules.pipewire.alsaDevices.second = {
        disableBatch = false;
        disableMmap = false;
        periodNum = 4;
        periodSize = 512;
        headroom = 0;
      };
    }
  ];
  invalidOptions =
    options:
    !(builtins.tryEval (
      builtins.deepSeq (t.cfgFor [ { modules.pipewire = options; } ]).modules.pipewire true
    )).success;
  conflict = {
    description = "Conflicting loopback";
    source = "input";
    target = "output";
    virtualSource.name = "virtual-input";
  };
  conflictConfig =
    enable:
    t.cfgFor [
      {
        modules.pipewire = {
          inherit enable;
          loopbacks = [ conflict ];
        };
      }
    ];
  conflictAssertion =
    cfg:
    builtins.any (
      a: !a.assertion && lib.hasInfix "cannot set both target and virtualSource" a.message
    ) cfg.assertions;
  invalidDevice = device: invalidOptions { alsaDevices.invalid = device; };
  invalidLoopback = loopback: invalidOptions { loopbacks = [ loopback ]; };
  minimalLoopback = {
    description = "Test";
    source = "input";
  };
in
assert !base.modules.pipewire.enable;
assert base.modules.pipewire.alsaDevices == { };
assert base.modules.pipewire.loopbacks == [ ];
assert enabled.services.pipewire.enable;
assert enabled.services.pipewire.alsa.enable;
assert enabled.services.pipewire.pulse.enable;
assert enabled.security.rtkit.enable;
assert !(enabled.services.pipewire.extraConfig.pipewire ? "99-loopbacks");
assert !disabled.services.pipewire.enable;
assert !disabled.security.rtkit.enable;
assert
  disabled.services.pipewire.wireplumber.extraConfig
  == base.services.pipewire.wireplumber.extraConfig;
assert
  disabled.services.pipewire.extraConfig.pipewire == base.services.pipewire.extraConfig.pipewire;
assert
  rules configured "scarlett-solo" == [
    {
      matches = [ { "device.name" = audio.alsaDevices.scarlett-solo.deviceName; } ];
      actions."update-props" = {
        "api.alsa.disable-batch" = true;
        "api.alsa.disable-mmap" = true;
        "api.alsa.period-num" = 8;
        "api.alsa.period-size" = 256;
        "api.alsa.headroom" = 128;
      };
    }
  ];
assert
  loopbacks configured == [
    {
      name = "libpipewire-module-loopback";
      args = {
        "node.description" = "KURO Loopback";
        "capture.props" = {
          "target.object" = source;
          "node.passive" = true;
        };
        "playback.props" = {
          "node.name" = "kuro_capture";
          "media.class" = "Audio/Source";
          "audio.position" = [
            "FL"
            "FR"
          ];
        };
      };
    }
    {
      name = "libpipewire-module-loopback";
      args = {
        "node.name" = "kuro_monitor";
        "node.description" = "KURO Monitor";
        "capture.props"."target.object" = source;
        "playback.props"."target.object" = target;
      };
    }
  ];
assert
  rules multiple "first" == [
    {
      matches = [ { "device.name" = "arbitrary-first-card"; } ];
      actions."update-props" = { };
    }
  ];
assert
  rules multiple "second" == [
    {
      matches = [ { "device.name" = "arbitrary-second-card"; } ];
      actions."update-props" = {
        "api.alsa.disable-batch" = false;
        "api.alsa.disable-mmap" = false;
        "api.alsa.period-num" = 4;
        "api.alsa.period-size" = 512;
        "api.alsa.headroom" = 0;
      };
    }
  ];
assert
  loopbacks multiple == [
    {
      name = "libpipewire-module-loopback";
      args = {
        "node.name" = "custom-loopback";
        "node.description" = "Custom source";
        "capture.props"."target.object" = "arbitrary-input";
        "playback.props" = {
          "node.name" = "custom-source";
          "media.class" = "Audio/Source";
          "audio.position" = [ "MONO" ];
        };
      };
    }
  ];
assert conflictAssertion (conflictConfig true);
assert !conflictAssertion (conflictConfig false);
assert invalidOptions { enable = "yes"; };
assert invalidDevice { };
assert invalidDevice { deviceName = ""; };
assert invalidDevice { deviceName = 1; };
assert invalidDevice {
  deviceName = "card";
  disableBatch = "yes";
};
assert invalidDevice {
  deviceName = "card";
  disableMmap = 1;
};
assert invalidDevice {
  deviceName = "card";
  periodNum = 0;
};
assert invalidDevice {
  deviceName = "card";
  periodSize = -1;
};
assert invalidDevice {
  deviceName = "card";
  periodSize = 1.5;
};
assert invalidDevice {
  deviceName = "card";
  headroom = -1;
};
assert invalidLoopback { source = "input"; };
assert invalidLoopback { description = "Test"; };
assert invalidLoopback (minimalLoopback // { description = ""; });
assert invalidLoopback (minimalLoopback // { source = ""; });
assert invalidLoopback (minimalLoopback // { name = ""; });
assert invalidLoopback (minimalLoopback // { target = ""; });
assert invalidLoopback (minimalLoopback // { capturePassive = "yes"; });
assert invalidLoopback (minimalLoopback // { virtualSource = { }; });
assert invalidLoopback (minimalLoopback // { virtualSource.name = ""; });
assert invalidLoopback (
  minimalLoopback
  // {
    virtualSource = {
      name = "virtual";
      channels = [ "" ];
    };
  }
);
true
