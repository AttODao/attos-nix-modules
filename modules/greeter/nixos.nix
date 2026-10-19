{
  config,
  attopkgs,
  lib,
  ...
}:
let
  cfg = config.modules.greeter;
  cursorPackage = attopkgs.custom-cursors { cursor = cfg.cursor; };
in
{
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.cursor != null;
        message = "modules.greeter.cursor is required when the greeter is enabled.";
      }
    ];
    services.displayManager.noctalia-greeter = {
      enable = true;

      settings = {
        user.default = lib.mkDefault "attodao";
        session.default = lib.mkDefault "Hyprland (uwsm-managed)";

        cursor = {
          theme = lib.mkDefault config.modules.desktop-theme.cursorName;
          size = lib.mkDefault config.modules.desktop-theme.cursorSize;
          path = lib.mkDefault "${cursorPackage}/share/icons";
        };
      }
      // lib.optionalAttrs (cfg.output != null) {
        output.name = lib.mkDefault cfg.output;
      };
    };
  };
}
