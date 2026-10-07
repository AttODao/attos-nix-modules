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
in
{
  config = lib.mkIf cfg.enable {
    home.packages = [
      pkgs.wl-clipboard
    ]
    ++ lib.optional cfg.screenRecorder.enable recorderPackage;

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
            video_source = lib.mkDefault "portal";
            video_codec = lib.mkDefault "h264";
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
          account = lib.mkDefault { };
        };

        location = lib.mkDefault { };

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
