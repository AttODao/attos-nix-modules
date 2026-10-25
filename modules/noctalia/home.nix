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
  externalWallpaper =
    osConfig.modules.hyprland.neowall.enable
    || config.services.linux-wallpaperengine.enable
    || cfg.wallpaperEngine.enable;
  idleBehaviors =
    lib.optionalAttrs (cfg.idle.lockAfter != null) {
      lock = {
        action = "lock";
        timeout = cfg.idle.lockAfter;
        enabled = true;
      };
    }
    // lib.optionalAttrs (cfg.idle.screenOffAfter != null) {
      "screen-off" = {
        action = "screen_off";
        timeout = cfg.idle.screenOffAfter;
        enabled = true;
      };
    }
    // lib.optionalAttrs (cfg.idle.suspendAfter != null) {
      "lock-and-suspend" = {
        action = "lock_and_suspend";
        timeout = cfg.idle.suspendAfter;
        enabled = true;
      };
    };
  # Every leaf (lists included) becomes a default so users can override parts without mkForce.
  sharedSettings = lib.mapAttrsRecursiveCond (value: !(value ? _type)) (_: lib.mkDefault);
in
{
  config = lib.mkIf cfg.enable {
    home.packages = [
      pkgs.wl-clipboard
    ]
    ++ lib.optional cfg.screenRecorder.enable recorderPackage
    ++ lib.optionals cfg.wallpaperEngine.enable [
      pkgs.linux-wallpaperengine
      pkgs.util-linux
      pkgs.procps
    ];

    systemd.user.tmpfiles.rules = lib.mkIf cfg.screenRecorder.enable [
      "d ${builtins.toJSON recordingsDirectory} 0755 - - -"
    ];

    systemd.user.services = lib.mkIf config.programs.noctalia.systemd.enable {
      noctalia = {
        Unit = {
          Requires = cfg.systemd.requires;
          After = cfg.systemd.after;
        };
      };
    };

    programs.noctalia = {
      enable = true;
      package = lib.mkIf (cfg.package != null) (lib.mkDefault cfg.package);
      systemd.enable = lib.mkDefault cfg.systemd.enable;
      customPalettes.Everforest = ./Everforest.json;

      settings = lib.mkMerge [
        (lib.mkIf cfg.screenRecorder.enable (sharedSettings {
          plugin_settings."noctalia/screen_recorder" = {
            directory = defaultRecordingsDirectory;
            video_source = cfg.screenRecorder.source;
            video_codec = cfg.screenRecorder.codec;
          };
          widget.screen_recorder.type = "noctalia/screen_recorder:recorder";
        }))
        (lib.mkIf cfg.headroom.enable (sharedSettings {
          widget.headroom.type = "ayagmar/headroom:usage";
          plugin_settings."ayagmar/headroom" = {
            provider_codex = "off";
            provider_antigravity = "off";
          };
        }))
        (lib.mkIf cfg.wallpaperEngine.enable (sharedSettings {
          widget.wallpaper_engine.type = "tadomika_ari/w-engine:w-engine-widget";
          plugin_settings."tadomika_ari/w-engine".sync_colors = false;
        }))
        (lib.mkIf (idleBehaviors != { }) (sharedSettings {
          idle.behavior = idleBehaviors;
        }))
        (sharedSettings {
          plugins = {
            auto_update = "official";
            enabled =
              lib.optional cfg.screenRecorder.enable "noctalia/screen_recorder"
              ++ lib.optional cfg.headroom.enable "ayagmar/headroom"
              ++ lib.optional cfg.systemdUnits.enable "srounce/systemd"
              ++ lib.optional cfg.wallpaperEngine.enable "tadomika_ari/w-engine";
          };
          wallpaper.enabled = !externalWallpaper;
          lockscreen.blurred_desktop = true;
          hot_corners = {
            enabled = true;
            delay_ms = 150;
            top_left.action = "launcher";
          };
          widget.network = {
            type = "network";
            show_vpn_label = true;
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
              ]
              ++ lib.optional cfg.headroom.enable "headroom"
              ++ [ "active_window" ];
              center = [
                "workspaces"
              ];
              end = [
                "media"
              ]
              ++ lib.optional cfg.screenRecorder.enable "screen_recorder"
              ++ lib.optional cfg.wallpaperEngine.enable "wallpaper_engine"
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
            polkit_agent = true;
            window_switcher.mru = true;
            screenshot.directory = "${config.xdg.userDirs.pictures}/Screenshots";
            panel = {
              transparency_mode = "glass";
              launcher_placement = "floating";
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
