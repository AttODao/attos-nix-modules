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
  # Every leaf (lists included) becomes a default so users can override parts without mkForce.
  sharedSettings = lib.mapAttrsRecursiveCond (value: !(value ? _type)) (_: lib.mkDefault);
in
{
  config = lib.mkIf cfg.enable {
    home.packages = [
      pkgs.wl-clipboard
    ]
    ++ lib.optional cfg.screenRecorder.enable recorderPackage;

    systemd.user.tmpfiles.rules = lib.mkIf cfg.screenRecorder.enable [
      "d ${builtins.toJSON recordingsDirectory} 0755 - - -"
    ];

    systemd.user.services = lib.mkIf config.programs.noctalia.systemd.enable {
      noctalia = {
        Unit = {
          Requires = cfg.systemd.requires;
          After = cfg.systemd.after;
        };
        # Restore the launcher when its required headless output is recreated.
        Install.WantedBy = lib.mkIf (lib.elem "hyprland-headless-output.service" cfg.systemd.requires) [
          "hyprland-headless-output.service"
        ];
      };
    };

    programs.noctalia = {
      enable = true;
      package = lib.mkIf (cfg.package != null) (lib.mkDefault cfg.package);
      systemd.enable = lib.mkDefault cfg.systemd.enable;
      customPalettes.Everforest = ./Everforest.json;

      settings = lib.mkMerge [
        {
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
        }
        (sharedSettings {
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
            pinned = cfg.dock.pinned;
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
            ) cfg.calendar.accounts;
          };

          location = lib.optionalAttrs (cfg.location.address != null) {
            address = cfg.location.address;
          };

          nightlight = {
            enabled = true;
            force = true;
            temperature_day = 6500;
            temperature_night = 4500;
          };
        })
      ];
    };
  };
}
