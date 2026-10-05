{
  osConfig,
  config,
  lib,
  pkgs,
  ...
}:
let
  yamlList = items: builtins.concatStringsSep "\n  - " (map builtins.toJSON items);
  noctalia = "${config.programs.noctalia.package}/bin/noctalia";
  kando = "${pkgs.kando}/bin/kando";
  solaarRules =
    builtins.replaceStrings
      [
        ''"@OPEN_NOCTALIA_LAUNCHER@"''
        ''"@OPEN_KANDO_MENU@"''
        ''"@CLOSE_KANDO_MENU@"''
      ]
      [
        (yamlList [
          noctalia
          "msg"
          "panel-toggle"
          "launcher"
        ])
        (yamlList [
          kando
          "--menu"
          "default"
        ])
        (yamlList [
          kando
          "--close-menu"
        ])
      ]
      (builtins.readFile ./rules.yaml);
in
{
  config = lib.mkIf osConfig.modules.solaar.enable {
    assertions = [
      {
        assertion = config.programs.noctalia.enable;
        message = "modules.solaar requires programs.noctalia.enable for the thumb gesture button.";
      }
    ];

    home.packages = [
      pkgs.solaar
      pkgs.kando
    ];

    systemd.user.services = {
      solaar = {
        Unit = {
          Description = "Solaar Logitech device manager";
          After = [ "graphical-session.target" ];
        };
        Service = {
          ExecStart = "${pkgs.solaar}/bin/solaar -w hide";
          Restart = "on-failure";
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };
      kando = {
        Unit = {
          Description = "Kando pie menu";
          After = [ "graphical-session.target" ];
        };
        Service = {
          ExecStart = kando;
          Restart = "on-failure";
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };
    };

    xdg.configFile = {
      "solaar/rules.yaml".text = solaarRules;
      "solaar/config.yaml".source = ./config.yaml;
    };

    wayland.windowManager.hyprland.settings.window_rule = [
      {
        match = {
          class = "^menu\\.kando\\.Kando$";
          title = "^Kando Menu$";
        };
        float = true;
        pin = true;
        move = "0 0";
        size = "100% 100%";
        border_size = 0;
        rounding = 0;
        no_anim = true;
        no_blur = true;
        opaque = true;
      }
    ];
  };
}
