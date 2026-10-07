{
  osConfig,
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = osConfig.modules.noctalia;
  defaultRecordingsDirectory = "${config.xdg.userDirs.videos}/Recordings";
  recordingsDirectory =
    config.programs.noctalia.settings.plugin_settings."noctalia/screen_recorder".directory;
  recorderPackage = osConfig.programs.gpu-screen-recorder.package;
  recordingToX = pkgs.writeShellApplication {
    name = "recording-to-x";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.ffmpeg-full
    ];
    text =
      builtins.replaceStrings
        [ "@RECORDINGS_DIRECTORY@" ]
        [
          (lib.escapeShellArg recordingsDirectory)
        ]
        (builtins.readFile ./recording-to-x.sh);
  };
  recorder = pkgs.writeShellApplication {
    name = "gpu-screen-recorder";
    runtimeInputs = [ pkgs.coreutils ];
    text =
      builtins.replaceStrings
        [ "@GPU_SCREEN_RECORDER@" "@RECORDING_TO_X@" "@RECORDINGS_DIRECTORY@" ]
        [
          (lib.escapeShellArg "${recorderPackage}/bin/gpu-screen-recorder")
          (lib.escapeShellArg "${recordingToX}/bin/recording-to-x")
          (lib.escapeShellArg recordingsDirectory)
        ]
        (builtins.readFile ./gpu-screen-recorder-auto-x.sh);
  };
in
{
  config = lib.mkIf cfg.enable {
    home.packages = [
      pkgs.wl-clipboard
    ]
    ++ lib.optional cfg.screenRecorder.enable recorderPackage
    ++ lib.optionals (cfg.screenRecorder.enable && cfg.screenRecorder.convertToX.enable) [
      recordingToX
      (lib.hiPrio recorder)
    ];

    home.activation.ensureNoctaliaRecordingsDir = lib.mkIf cfg.screenRecorder.enable (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        ${pkgs.coreutils}/bin/install -d -m 755 ${lib.escapeShellArg recordingsDirectory}
      ''
    );

    programs.noctalia = {
      enable = true;
      customPalettes.Everforest = ./Everforest.json;

      settings = {
        plugins.enabled = lib.optional cfg.screenRecorder.enable "noctalia/screen_recorder";
        plugin_settings = lib.mkIf cfg.screenRecorder.enable {
          "noctalia/screen_recorder" = {
            directory = lib.mkDefault defaultRecordingsDirectory;
            video_source = lib.mkDefault cfg.screenRecorder.source;
            video_codec = lib.mkDefault cfg.screenRecorder.codec;
          };
        };
        widget = lib.mkIf cfg.screenRecorder.enable {
          screen_recorder.type = "noctalia/screen_recorder:recorder";
        };

        bar = {
          order = [ "main" ];
          main = {
            position = "top";
            thickness = 34;
            background_opacity = 0.92;
            radius = 10;
            margin_ends = 12;
            margin_edge = 6;
            padding = 12;
            widget_spacing = 6;
            shadow = true;
            reserve_space = true;
            start = [
              "launcher"
              "clock"
              "sysmon"
              "active_window"
            ];
            center = [
              "workspaces"
            ];
            end = [
              "media"
            ]
            ++ lib.optional cfg.screenRecorder.enable "screen_recorder"
            ++ [
              "tray"
              "notifications"
              "clipboard"
              "network"
              "bluetooth"
              "volume"
              "brightness"
              "battery"
              "control-center"
              "session"
            ];
          };
        };

        shell = {
          avatar_path = "${config.home.homeDirectory}/.face";
          time_format = "{:%H:%M}";
          date_format = "%Y-%m-%d";
          launch_apps_as_systemd_services = true;
          panel = {
            transparency_mode = "glass";
            launcher_placement = "centered";
            control_center_placement = "attached";
            session_placement = "attached";
          };
        };

        dock = {
          enabled = true;
          position = "bottom";
          launcher_position = "start";
          active_monitor_only = false;
          show_running = true;
          show_dots = true;
          pinned = lib.mkDefault cfg.dock.pinned;
        };

        theme = {
          mode = "dark";
          source = "custom";
          custom_palette = "Everforest";
        };

        weather = {
          enabled = true;
          unit = "celsius";
        };

        calendar = {
          enabled = true;
          refresh_minutes = 15;
          account = lib.mapAttrs (
            _: account:
            lib.mapAttrs (_: lib.mkDefault) (
              {
                type = "caldav";
                provider = "custom";
                inherit (account)
                  name
                  color
                  username
                  calendars
                  ;
                server_url = account.serverUrl;
              }
              // lib.optionalAttrs (account.passwordFile != null) {
                credential_source = "file";
                password_file = account.passwordFile;
              }
            )
          ) cfg.calendar.accounts;
        };

        location = lib.optionalAttrs (cfg.location.address != null) {
          address = lib.mkDefault cfg.location.address;
        };

        nightlight = {
          enabled = true;
          force = true;
          temperature_day = 6500;
          temperature_night = 4500;
        };
      };
    };
  };
}
