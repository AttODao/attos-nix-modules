# nix-instantiate --eval --strict tests/noctalia.nix \
#   --arg nixpkgs /path/to/nixpkgs --arg homeManager /path/to/home-manager
{
  nixpkgs,
  homeManager,
  system ? builtins.currentSystem,
}:
let
  t = import ./lib.nix { inherit nixpkgs homeManager system; };
  inherit (t) pkgs lib;
  account = {
    name = "Test Calendar";
    color = "#3584e4";
    serverUrl = "https://calendar.example.test/";
    username = "test";
    passwordFile = "/run/secrets/calendar-password";
  };
  nativeAccount = {
    type = "caldav";
    provider = "custom";
    inherit (account) name color username;
    server_url = account.serverUrl;
    calendars = [ ];
    credential_source = "file";
    password_file = account.passwordFile;
  };
  publicSettings = {
    enable = true;
    dock.pinned = [ "footclient" ];
    location.address = "Tokyo, Japan";
    calendar.accounts = {
      test = account;
      withoutPassword = account // {
        passwordFile = null;
        calendars = [ "work" ];
      };
    };
    screenRecorder.enable = true;
  };
  base = t.cfgFor [ ];
  enabledOS = t.cfgFor [ { modules.noctalia.enable = true; } ];
  enabled = t.hm enabledOS "test";
  pinnedPackage = pkgs.noctalia.overrideAttrs {
    version = "5.1.0";
    __intentionallyOverridingVersion = true;
  };
  serviceOS =
    (t.evalSystem {
      users = [
        "test"
        "second"
      ];
      modules = [
        {
          modules.noctalia = {
            enable = true;
            package = pinnedPackage;
            systemd = {
              enable = true;
              requires = [ "hyprland-headless-output.service" ];
              after = [ "hyprland-headless-output.service" ];
            };
          };
        }
      ];
    }).config;
  disabledInputs = t.hmFor [
    {
      modules.noctalia = {
        package = pinnedPackage;
        systemd = {
          enable = true;
          requires = [ "unused.service" ];
          after = [ "unused.service" ];
        };
      };
    }
  ];
  launcherOverride = t.hmFor [
    {
      modules.noctalia = {
        enable = true;
        package = pinnedPackage;
        systemd = {
          enable = true;
          requires = [ "unused.service" ];
        };
      };
      home-manager.users.test.programs.noctalia = {
        package = pkgs.noctalia;
        systemd.enable = false;
      };
    }
  ];
  recordingOS = t.cfgFor [
    {
      modules.noctalia = publicSettings;
      home-manager.users.test.xdg.userDirs.videos = "/home/test/My Videos";
    }
  ];
  recording = t.hm recordingOS "test";
  recorderPackage = pkgs.gpu-screen-recorder.overrideAttrs (_: {
    pname = "gpu-screen-recorder-test";
  });
  convertedOS =
    (t.evalSystem {
      users = [
        "test"
        "second"
      ];
      modules = [
        {
          modules.noctalia = publicSettings // {
            screenRecorder = {
              enable = true;
              source = "focused";
              codec = "hevc_hdr";
              convertToX.enable = true;
            };
          };
          programs.gpu-screen-recorder.package = recorderPackage;
          # Directly declared HM users must also receive the shared feature.
          users.users.direct.isNormalUser = true;
          home-manager.users = {
            direct = { };
            test.programs.noctalia.settings.plugin_settings."noctalia/screen_recorder".directory =
              "/home/test/My ' Recordings";
            second.xdg.userDirs.videos = "/home/second/Videos";
          };
        }
      ];
    }).config;
  converted = t.hm convertedOS "test";
  overridden = t.hmFor [
    {
      modules.noctalia = publicSettings;
      programs.gpu-screen-recorder.package = recorderPackage;
      home-manager.users.test.programs.noctalia.settings = {
        plugin_settings."noctalia/screen_recorder" = {
          directory = "/home/test/My Recordings";
          video_source = "custom-source";
          video_codec = "custom-codec";
        };
        dock.pinned = [ "pcmanfm" ];
        calendar.account.test.username = "operator";
        location.address = "Osaka, Japan";
      };
    }
  ];
  settings = recording.programs.noctalia.settings;
  plugin = hm: hm.programs.noctalia.settings.plugin_settings."noctalia/screen_recorder";
  packageNamed = hm: name: lib.findFirst (p: p.name == name) null hm.home.packages;
  converter = packageNamed converted "recording-to-x";
  wrapper = packageNamed converted "gpu-screen-recorder";
  renderConverter =
    directory:
    builtins.replaceStrings
      [ "@RECORDINGS_DIRECTORY@" ]
      [
        (lib.escapeShellArg directory)
      ]
      (builtins.readFile ../modules/noctalia/recording-to-x.sh);
  renderWrapper =
    directory: converterPackage:
    builtins.unsafeDiscardStringContext (
      builtins.replaceStrings
        [ "@GPU_SCREEN_RECORDER@" "@RECORDING_TO_X@" "@RECORDINGS_DIRECTORY@" ]
        [
          (lib.escapeShellArg "${recorderPackage}/bin/gpu-screen-recorder")
          (lib.escapeShellArg "${converterPackage}/bin/recording-to-x")
          (lib.escapeShellArg directory)
        ]
        (builtins.readFile ../modules/noctalia/gpu-screen-recorder-auto-x.sh)
    );
  invalid =
    value:
    builtins.tryEval (
      builtins.deepSeq (t.cfgFor [ { modules.noctalia = value; } ]).modules.noctalia true
    );
  invalidPassword =
    passwordFile:
    invalid {
      calendar.accounts.test = account // {
        inherit passwordFile;
      };
    };
  failedConversion = t.cfgFor [
    {
      modules.noctalia = {
        enable = true;
        screenRecorder.convertToX.enable = true;
      };
    }
  ];
in
assert lib.all
  (
    user:
    let
      hm = t.hm serviceOS user;
    in
    hm.programs.noctalia.package.drvPath == pinnedPackage.drvPath
    && hm.programs.noctalia.package.version == "5.1.0"
    && hm.programs.noctalia.systemd.enable
    && hm.systemd.user.services.noctalia.Unit.Requires == [ "hyprland-headless-output.service" ]
    && lib.elem "hyprland-headless-output.service" hm.systemd.user.services.noctalia.Unit.After
    && hm.systemd.user.services.noctalia.Service.ExecStart == [ (lib.getExe pinnedPackage) ]
  )
  [
    "test"
    "second"
  ];
assert !disabledInputs.programs.noctalia.enable;
assert !(disabledInputs.systemd.user.services ? noctalia);
assert !launcherOverride.programs.noctalia.systemd.enable;
assert launcherOverride.programs.noctalia.package.drvPath == pkgs.noctalia.drvPath;
assert !(launcherOverride.systemd.user.services ? noctalia);
assert !(invalid { package = "not-a-package"; }).success;
assert !(invalid { systemd.requires = [ 1 ]; }).success;
assert !(invalid { systemd.after = [ "" ]; }).success;
assert !base.modules.noctalia.enable && !base.home-manager.users.test.programs.noctalia.enable;
assert !base.programs.gpu-screen-recorder.enable;
assert base.modules.noctalia.location.address == null;
assert base.modules.noctalia.calendar.accounts == { };
assert !base.modules.noctalia.screenRecorder.enable;
assert !base.modules.noctalia.screenRecorder.convertToX.enable;
assert base.modules.noctalia.screenRecorder.source == "portal";
assert base.modules.noctalia.screenRecorder.codec == "h264";
assert !enabledOS.programs.gpu-screen-recorder.enable;
assert enabled.programs.noctalia.enable;
assert !enabled.programs.noctalia.systemd.enable;
assert enabled.programs.noctalia.settings.plugins.enabled == [ ];
assert !(enabled.programs.noctalia.settings.widget or { } ? screen_recorder);
assert !(enabled.home.activation ? ensureNoctaliaRecordingsDir);
assert !(lib.elem pkgs.gpu-screen-recorder enabled.home.packages);
assert packageNamed enabled "recording-to-x" == null;
assert packageNamed enabled "gpu-screen-recorder" == null;
assert enabled.programs.noctalia.settings.calendar.account == { };
assert enabled.programs.noctalia.settings.location == { };
assert enabled.programs.noctalia.settings.theme.custom_palette == "Everforest";
assert !recordingOS.programs.gpu-screen-recorder.enable;
assert settings.dock.pinned == [ "footclient" ];
assert settings.calendar.account.test == nativeAccount;
assert
  settings.calendar.account.withoutPassword == (builtins.removeAttrs nativeAccount [
    "credential_source"
    "password_file"
  ])
  // {
    calendars = [ "work" ];
  };
assert settings.location.address == "Tokyo, Japan";
assert settings.plugins.enabled == [ "noctalia/screen_recorder" ];
assert (plugin recording).directory == "/home/test/My Videos/Recordings";
assert (plugin recording).video_source == "portal";
assert (plugin recording).video_codec == "h264";
assert settings.widget.screen_recorder.type == "noctalia/screen_recorder:recorder";
assert lib.elem "screen_recorder" settings.bar.main.end;
assert lib.elem pkgs.gpu-screen-recorder recording.home.packages;
assert lib.elem pkgs.wl-clipboard recording.home.packages;
assert packageNamed recording "recording-to-x" == null;
assert lib.hasInfix "'/home/test/My Videos/Recordings'"
  recording.home.activation.ensureNoctaliaRecordingsDir.data;
assert recording.xdg.configFile."noctalia/palettes/Everforest.json".enable;
assert builtins.hasAttr "dark" (
  builtins.fromJSON (builtins.readFile ../modules/noctalia/Everforest.json)
);
assert enabled.home.activationPackage.drvPath != "";
assert recording.home.activationPackage.drvPath != "";
assert lib.elem recorderPackage overridden.home.packages;
assert !(lib.elem pkgs.gpu-screen-recorder overridden.home.packages);
assert overridden.programs.noctalia.settings.dock.pinned == [ "pcmanfm" ];
assert
  overridden.programs.noctalia.settings.calendar.account.test
  == nativeAccount // { username = "operator"; };
assert overridden.programs.noctalia.settings.location.address == "Osaka, Japan";
assert (plugin overridden).video_source == "custom-source";
assert (plugin overridden).video_codec == "custom-codec";
assert lib.hasInfix "'/home/test/My Recordings'"
  overridden.home.activation.ensureNoctaliaRecordingsDir.data;
assert convertedOS.programs.gpu-screen-recorder.enable;
assert lib.elem recorderPackage converted.home.packages;
assert !(lib.elem pkgs.gpu-screen-recorder converted.home.packages);
assert (plugin converted).video_source == "focused";
assert (plugin converted).video_codec == "hevc_hdr";
assert converter != null && wrapper != null;
assert wrapper.meta.priority == -10;
assert lib.hasInfix (renderConverter (plugin converted).directory) converter.text;
assert lib.hasInfix (renderWrapper (plugin converted).directory converter) wrapper.text;
assert lib.hasInfix (builtins.unsafeDiscardStringContext (
  lib.makeBinPath [
    pkgs.coreutils
    pkgs.ffmpeg-full
  ]
)) converter.text;
assert lib.hasInfix (lib.escapeShellArg (plugin converted)
  .directory) converted.home.activation.ensureNoctaliaRecordingsDir.data;
assert lib.all
  (
    name:
    let
      hm = t.hm convertedOS name;
      directory = (plugin hm).directory;
      userConverter = packageNamed hm "recording-to-x";
      userWrapper = packageNamed hm "gpu-screen-recorder";
    in
    hm.programs.noctalia.enable
    && directory == "${hm.xdg.userDirs.videos}/Recordings"
    && hm.programs.noctalia.settings.calendar.account.test == nativeAccount
    && lib.hasInfix (renderConverter directory) userConverter.text
    && lib.hasInfix (renderWrapper directory userConverter) userWrapper.text
    && userWrapper.meta.priority == -10
    && lib.hasInfix (lib.escapeShellArg directory) hm.home.activation.ensureNoctaliaRecordingsDir.data
    && hm.home.activationPackage.drvPath != ""
  )
  [
    "second"
    "direct"
  ];
assert converted.home.activationPackage.drvPath != "";
assert lib.any (
  a: !a.assertion && lib.hasInfix "convertToX.enable requires" a.message
) failedConversion.assertions;
assert !(invalid { enable = "yes"; }).success;
assert !(invalid { dock.pinned = [ 1 ]; }).success;
assert !(invalid { screenRecorder.enable = "yes"; }).success;
assert !(invalid { screenRecorder.source = ""; }).success;
assert !(invalid { screenRecorder.codec = 1; }).success;
assert !(invalid { screenRecorder.convertToX.enable = "yes"; }).success;
assert !(invalid { location.address = 1; }).success;
assert !(invalid { calendar.accounts.test = builtins.removeAttrs account [ "name" ]; }).success;
assert
  !(invalid {
    calendar.accounts.test = account // {
      color = 1;
    };
  }).success;
assert
  !(invalid {
    calendar.accounts.test = account // {
      serverUrl = "";
    };
  }).success;
assert
  !(invalid {
    calendar.accounts.test = account // {
      username = 1;
    };
  }).success;
assert
  !(invalid {
    calendar.accounts.test = account // {
      calendars = [ 1 ];
    };
  }).success;
assert
  !(invalid {
    calendar.accounts.test = account // {
      provider = "custom";
    };
  }).success;
assert lib.all (path: !(invalidPassword path).success) [
  "relative/password"
  "/nix/store"
  "/nix/store/fake-password"
  "/run/secrets/bad:path"
  "/run/secrets/bad\npath"
  "/run/secrets/bad\rpath"
  ../modules/noctalia/Everforest.json
];
assert !(invalid { calendar.account = { }; }).success;
assert !(invalid { extraConfig = ""; }).success;
true
