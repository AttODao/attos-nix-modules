{
  osConfig,
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = osConfig.modules.hyprland;
  mod = "SUPER";
  systemctl = "${pkgs.systemd}/bin/systemctl";
  noctalia = cmd: "noctalia msg ${cmd}";
  powerButtonCommand = "${noctalia "session lock"} && sleep 1 && ${noctalia "monitors off"}";
  lidMonitorCommand = action: "sleep 1 && ${noctalia "monitors ${action}"}";
  lua = lib.generators.mkLuaInline;
  # Shared settings override the preset; per-user HM settings can override both.
  sharedSettings =
    defaults:
    lib.mapAttrsRecursiveCond (value: !(value ? _type)) (_: lib.mkDefault) (
      lib.recursiveUpdate defaults cfg.settings
      // {
        # Controller input is not Wayland activity. Keep this additive with consumer rules.
        window_rule = [
          {
            match.class = ".*";
            idle_inhibit = "fullscreen";
          }
        ]
        ++ (cfg.settings.window_rule or [ ]);
      }
    );

  luaBind = keys: dispatcher: options: {
    _args = [
      (lua keys)
      (lua dispatcher)
    ]
    ++ lib.optional (options != null) options;
  };

  modBind = key: dispatcher: luaBind ''mod .. " + ${key}"'' dispatcher null;
  modCommand = key: command: modBind key "hl.dsp.exec_cmd(${builtins.toJSON command})";
  lockedCommand =
    key: command:
    luaBind (builtins.toJSON key) "hl.dsp.exec_cmd(${builtins.toJSON command})" { locked = true; };
  workspaceBinds = lib.concatMap (
    n:
    let
      ws = toString n;
    in
    [
      (modBind ws "hl.dsp.focus({ workspace = ${ws} })")
      (modBind "SHIFT + ${ws}" "hl.dsp.window.move({ workspace = ${ws} })")
    ]
  ) (lib.range 1 9);

  startupCommands = [
    "${systemctl} --user start fcitx5-daemon.service xdg-desktop-portal.service xdg-desktop-portal-gtk.service xdg-desktop-portal-hyprland.service"
  ]
  ++ lib.optional (!config.programs.noctalia.systemd.enable) "uwsm app -t service -- noctalia"
  ++ lib.optional cfg.neowall.enable "uwsm app -t service -- neowall";
  startupHook = lua (
    "function()\n"
    + lib.concatMapStringsSep "\n" (
      command: "  hl.exec_cmd(${builtins.toJSON command})"
    ) startupCommands
    + "\nend"
  );
in
{
  config = lib.mkIf cfg.enable {
    home.packages = lib.optional cfg.neowall.enable pkgs.neowall;

    xdg.configFile = lib.mkIf cfg.neowall.enable {
      "neowall/config.vibe".text = ''
        default {
          shader ${pkgs.neowall}/share/neowall/shaders/neonwave_sunrise.glsl
          shader_speed 1.0
        }
      '';
    };

    wayland.windowManager.hyprland = {
      enable = true;
      package = lib.mkDefault osConfig.programs.hyprland.package;
      portalPackage = lib.mkDefault osConfig.programs.hyprland.portalPackage;
      configType = "lua";

      systemd.enable = false;
      xwayland.enable = true;

      # Default individual leaves/lists, keeping Lua marker attrsets atomic.
      settings = sharedSettings {
        mod._var = mod;

        config = {
          animations.enabled = true;

          cursor = {
            enable_hyprcursor = true;
            no_hardware_cursors = true;
          };

          decoration = {
            rounding = 10;
            rounding_power = 2;
            active_opacity = 1.0;
            inactive_opacity = 0.96;
            fullscreen_opacity = 1.0;

            shadow = {
              enabled = true;
              range = 18;
              render_power = 3;
              color = "rgba(0b1010aa)";
              color_inactive = "rgba(0b101066)";
              offset = [
                0
                3
              ];
              scale = 0.98;
            };

            blur = {
              enabled = true;
              size = 8;
              passes = 3;
              noise = 0.0117;
              contrast = 0.95;
              brightness = 0.82;
              vibrancy = 0.16;
              new_optimizations = true;
              ignore_opacity = true;
              xray = false;
            };
          };

          general = {
            gaps_in = 4;
            gaps_out = 8;
            border_size = 2;
            col = {
              active_border = {
                colors = [
                  "rgba(a7c080ee)"
                  "rgba(83c092ee)"
                ];
                angle = 45;
              };
              inactive_border = "rgba(3c4841aa)";
            };
            resize_on_border = true;
          };

          input = {
            follow_mouse = 2;
            special_fallthrough = true;
            focus_on_close = 1;

            touchpad = {
              natural_scroll = true;
            };
          };

          misc = {
            disable_hyprland_logo = true;
            disable_splash_rendering = true;
            focus_on_activate = true;
          };
        };

        gesture = {
          fingers = 3;
          direction = "horizontal";
          action = "workspace";
        };

        env = [
          {
            _args = [
              "ELECTRON_OZONE_PLATFORM_HINT"
              "auto"
            ];
          }
        ];

        monitor = [
          {
            output = "";
            mode = "preferred";
            position = "auto";
            scale = 1;
          }
        ];

        curve = [
          {
            _args = [
              "easeOutQuint"
              {
                type = "bezier";
                points = [
                  [
                    0.23
                    1
                  ]
                  [
                    0.32
                    1
                  ]
                ];
              }
            ];
          }
          {
            _args = [
              "easeInOutCubic"
              {
                type = "bezier";
                points = [
                  [
                    0.65
                    0.05
                  ]
                  [
                    0.36
                    1
                  ]
                ];
              }
            ];
          }
          {
            _args = [
              "linear"
              {
                type = "bezier";
                points = [
                  [
                    0
                    0
                  ]
                  [
                    1
                    1
                  ]
                ];
              }
            ];
          }
        ];

        animation = [
          {
            leaf = "windows";
            enabled = true;
            speed = 4;
            bezier = "easeOutQuint";
            style = "popin 85%";
          }
          {
            leaf = "windowsOut";
            enabled = true;
            speed = 3;
            bezier = "easeInOutCubic";
            style = "popin 85%";
          }
          {
            leaf = "border";
            enabled = true;
            speed = 5;
            bezier = "easeOutQuint";
          }
          {
            leaf = "fade";
            enabled = true;
            speed = 4;
            bezier = "easeOutQuint";
          }
          {
            leaf = "workspaces";
            enabled = true;
            speed = 4;
            bezier = "easeOutQuint";
            style = "slide";
          }
        ];

        bind = [
          (modCommand "Return" "uwsm app -t service -- footclient")
          (modCommand "E" "uwsm app -t service -- footclient --app-id=yazi yazi")

          (modCommand "Space" (noctalia "panel-toggle launcher"))
          (modCommand "S" (noctalia "panel-toggle control-center"))
          (modCommand "Comma" (noctalia "settings-toggle"))

          (modCommand "V" (noctalia "panel-toggle clipboard"))
          (modCommand "Period" (noctalia "panel-toggle launcher /emo "))

          (modCommand "K" (noctalia "panel-toggle control-center calendar"))
          (modCommand "M" (noctalia "panel-toggle control-center system"))

          (modCommand "Escape" (noctalia "panel-toggle session"))
          (modCommand "L" (noctalia "session lock"))

          (modCommand "SHIFT + D" (noctalia "plugin noctalia/screen_recorder:service all toggle"))

          (modBind "Q" "hl.dsp.window.close()")
          (modBind "F" ''hl.dsp.window.fullscreen({ mode = "maximized" })'')
          (modBind "SHIFT + F" ''hl.dsp.window.fullscreen({ mode = "fullscreen" })'')
          (modBind "C" "hl.dsp.window.center()")
          (modBind "R" ''hl.dsp.window.float({ action = "toggle" })'')

          (modBind "Left" ''hl.dsp.focus({ direction = "left" })'')
          (modBind "Right" ''hl.dsp.focus({ direction = "right" })'')
          (modBind "Up" ''hl.dsp.focus({ direction = "up" })'')
          (modBind "Down" ''hl.dsp.focus({ direction = "down" })'')

          (modBind "SHIFT + Left" ''hl.dsp.window.move({ direction = "left" })'')
          (modBind "SHIFT + Right" ''hl.dsp.window.move({ direction = "right" })'')
          (modBind "SHIFT + Up" ''hl.dsp.window.move({ direction = "up" })'')
          (modBind "SHIFT + Down" ''hl.dsp.window.move({ direction = "down" })'')

          (modBind "mouse_down" ''hl.dsp.focus({ workspace = "r+1" })'')
          (modBind "mouse_up" ''hl.dsp.focus({ workspace = "r-1" })'')
        ]
        ++ workspaceBinds
        ++ [

          (modCommand "SHIFT + S" (noctalia "screenshot-region"))
          (modCommand "ALT + SHIFT + S" (noctalia "screenshot-annotate"))
          (modCommand "CTRL + SHIFT + S" (noctalia "screenshot-fullscreen"))
          (luaBind ''"ALT + Tab"'' ''hl.dsp.exec_cmd("noctalia msg window-switcher hold")'' null)

          (modCommand "SHIFT + R" "hyprctl reload")
          (modBind "SHIFT + E" "hl.dsp.exit()")

          (lockedCommand "XF86AudioRaiseVolume" (noctalia "volume-up"))
          (lockedCommand "XF86AudioLowerVolume" (noctalia "volume-down"))
          (lockedCommand "XF86AudioMute" (noctalia "volume-mute"))
          (lockedCommand "XF86AudioMicMute" (noctalia "microphone-mute"))
          (lockedCommand "XF86MonBrightnessUp" (noctalia "brightness-up"))
          (lockedCommand "XF86MonBrightnessDown" (noctalia "brightness-down"))

          (lockedCommand "XF86AudioPlay" (noctalia "media toggle"))
          (lockedCommand "XF86AudioNext" (noctalia "media next"))
          (lockedCommand "XF86AudioPrev" (noctalia "media prev"))
          (lockedCommand "XF86PowerOff" powerButtonCommand)

          (luaBind ''mod .. " + mouse:272"'' "hl.dsp.window.drag()" { mouse = true; })
          (luaBind ''mod .. " + mouse:273"'' "hl.dsp.window.resize()" { mouse = true; })
        ]
        ++ lib.optionals cfg.lidSwitch.enable [
          (lockedCommand "switch:on:Lid Switch" (lidMonitorCommand "off"))
          (lockedCommand "switch:off:Lid Switch" (lidMonitorCommand "on"))
        ];

        on = {
          _args = [
            "hyprland.start"
            startupHook
          ];
        };
      };
    };
  };
}
