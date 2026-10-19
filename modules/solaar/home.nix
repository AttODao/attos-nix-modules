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

    home.packages = [ pkgs.kando ];

    systemd.user.services = {
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

    # Solaar saves device settings and rules in place; store symlinks would be read-only.
    xdg.configFile = {
      "solaar/rules.yaml" = {
        text = lib.mkDefault solaarRules;
        enable = false;
      };
      "solaar/config.yaml" = {
        source = lib.mkDefault ./config.yaml;
        enable = false;
      };
    };
    home.activation.installSolaarConfig = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      run ${pkgs.coreutils}/bin/install -d -m 700 "${config.xdg.configHome}/solaar"
      run ${pkgs.coreutils}/bin/install -m 600 ${
        config.xdg.configFile."solaar/rules.yaml".source
      } "${config.xdg.configHome}/solaar/rules.yaml"
      run ${pkgs.coreutils}/bin/install -m 600 ${
        config.xdg.configFile."solaar/config.yaml".source
      } "${config.xdg.configHome}/solaar/config.yaml"
    '';

    wayland.windowManager.hyprland.settings.window_rule = lib.mkDefault [
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
