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
  account.test = {
    type = "caldav";
    server_url = "https://calendar.example.test/";
    username = "test";
    credential_source = "file";
    password_file = "/run/secrets/calendar-password";
  };
  location.address = "Tokyo, Japan";
  base = t.cfgFor [ ];
  enabled = t.hmFor [ { modules.noctalia.enable = true; } ];
  recording = t.hmFor [
    { home-manager.users.test.xdg.userDirs.videos = "/home/test/My Videos"; }
    {
      modules.noctalia = {
        enable = true;
        screenRecorder.enable = true;
        dock.pinned = [ "footclient" ];
      };
      home-manager.users.test.programs.noctalia.settings = {
        calendar.account = account;
        inherit location;
      };
    }
  ];
  recorderPackage = pkgs.gpu-screen-recorder.overrideAttrs (_: {
    version = "test";
  });
  overridden = t.hmFor [
    {
      modules.noctalia = {
        enable = true;
        screenRecorder.enable = true;
        dock.pinned = [ "footclient" ];
      };
      programs.gpu-screen-recorder.package = recorderPackage;
      home-manager.users.test.programs.noctalia.settings = {
        plugin_settings."noctalia/screen_recorder" = {
          directory = "/home/test/My Recordings";
          video_source = "focused";
          video_codec = "hevc_hdr";
        };
        dock.pinned = [ "pcmanfm" ];
        calendar.account.test = account.test // {
          username = "operator";
        };
        location.address = "Osaka, Japan";
      };
    }
  ];
  settings = recording.programs.noctalia.settings;
  invalid =
    value:
    builtins.tryEval (
      builtins.deepSeq (t.cfgFor [ { modules.noctalia = value; } ]).modules.noctalia true
    );
in
assert !base.modules.noctalia.enable && !base.home-manager.users.test.programs.noctalia.enable;
assert enabled.programs.noctalia.enable;
assert !enabled.programs.noctalia.systemd.enable;
assert enabled.programs.noctalia.settings.plugins.enabled == [ ];
assert !(enabled.programs.noctalia.settings.widget or { } ? screen_recorder);
assert !(enabled.home.activation ? ensureNoctaliaRecordingsDir);
assert !(lib.elem pkgs.gpu-screen-recorder enabled.home.packages);
assert enabled.programs.noctalia.settings.calendar.account == { };
assert enabled.programs.noctalia.settings.location == { };
assert enabled.programs.noctalia.settings.theme.custom_palette == "Everforest";
assert settings.dock.pinned == [ "footclient" ];
assert settings.calendar.account == account && settings.location == location;
assert settings.plugins.enabled == [ "noctalia/screen_recorder" ];
assert
  settings.plugin_settings."noctalia/screen_recorder".directory == "/home/test/My Videos/Recordings";
assert settings.widget.screen_recorder.type == "noctalia/screen_recorder:recorder";
assert lib.elem "screen_recorder" settings.bar.main.end;
assert lib.elem pkgs.gpu-screen-recorder recording.home.packages;
assert lib.elem pkgs.wl-clipboard recording.home.packages;
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
assert overridden.programs.noctalia.settings.calendar.account.test.username == "operator";
assert
  overridden.programs.noctalia.settings.calendar.account.test.server_url == account.test.server_url;
assert
  overridden.programs.noctalia.settings.calendar.account.test.password_file
  == account.test.password_file;
assert overridden.programs.noctalia.settings.location.address == "Osaka, Japan";
assert overridden.programs.noctalia.settings.theme.custom_palette == "Everforest";
assert
  overridden.programs.noctalia.settings.plugin_settings."noctalia/screen_recorder".video_source
  == "focused";
assert
  overridden.programs.noctalia.settings.plugin_settings."noctalia/screen_recorder".video_codec
  == "hevc_hdr";
assert lib.hasInfix "'/home/test/My Recordings'"
  overridden.home.activation.ensureNoctaliaRecordingsDir.data;
assert !(invalid { enable = "yes"; }).success;
assert !(invalid { dock.pinned = [ 1 ]; }).success;
assert !(invalid { screenRecorder.enable = "yes"; }).success;
assert !(invalid { calendar.account = { }; }).success;
assert !(invalid { location = { }; }).success;
assert !(invalid { extraConfig = ""; }).success;
true
