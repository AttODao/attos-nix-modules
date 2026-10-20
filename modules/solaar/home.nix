{
  osConfig,
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = osConfig.modules.solaar;
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
  # Solaar saves device settings and rules in place; store symlinks would be read-only.
  seeded = config.lib.attos.mutableXdgConfigFiles {
    name = "solaar";
    files = {
      "solaar/rules.yaml" = null;
    }
    // lib.optionalAttrs (cfg.deviceConfig != null) { "solaar/config.yaml" = null; };
  };
in
{
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.programs.noctalia.enable;
        message = "modules.solaar requires programs.noctalia.enable for the thumb gesture button.";
      }
    ];

    home.packages = [ pkgs.kando ];

    systemd.user.services.kando = config.lib.attos.graphicalAppService {
      description = "Kando pie menu";
      exec = kando;
    };

    xdg.configFile = lib.mkMerge [
      seeded.xdg.configFile
      {
        "solaar/rules.yaml".text = lib.mkDefault solaarRules;
        "solaar/config.yaml" = lib.mkIf (cfg.deviceConfig != null) {
          source = lib.mkDefault cfg.deviceConfig;
        };
      }
    ];
    home.activation = seeded.home.activation;

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
