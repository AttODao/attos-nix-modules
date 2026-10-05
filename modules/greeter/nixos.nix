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
    services.displayManager.noctalia-greeter = {
      enable = true;

      settings = {
        user.default = "attodao";
        session.default = "Hyprland (uwsm-managed)";

        cursor = {
          theme = "Custom-Cursors";
          size = 48;
          path = "${cursorPackage}/share/icons";
        };
      }
      // lib.optionalAttrs (cfg.output != null) {
        output.name = cfg.output;
      };
    };
  };
}
