{
  osConfig,
  config,
  lib,
  pkgs,
  attopkgs,
  ...
}:
let
  cfg = osConfig.modules.attos-mouse;
  pkg = attopkgs.attos-mouse;
  defaults = {
    exec.wrapper = [
      "${osConfig.programs.uwsm.package}/bin/uwsm"
      "app"
      "--"
    ];
    style = {
      font = "${pkgs.noto-fonts-cjk-sans-static}/share/fonts/opentype/noto-cjk/NotoSansCJK-Medium.ttc";
      background = "#2d353bb3";
      slot = "#3d484dcc";
      accent = "#a7c080ff";
      foreground = "#d3c6aaff";
    }
    // lib.optionalAttrs (config.gtk.iconTheme != null) {
      icon_theme = config.gtk.iconTheme.name;
    };
  };
  settings = lib.recursiveUpdate defaults cfg.settings;
  toml = (pkgs.formats.toml { }).generate "attos-mouse-config.toml" settings;
  checked = pkgs.runCommand "attos-mouse-config-checked.toml" { } ''
    ${pkg}/bin/attos-mouse check-config ${toml}
    cp ${toml} "$out"
  '';
in
{
  config = lib.mkIf osConfig.modules.attos-mouse.enable {
    xdg.configFile."attos-mouse/config.toml".source = lib.mkDefault checked;
    home.packages = [ pkg ];
    systemd.user.services.attos-mouse = config.lib.attos.graphicalAppService {
      description = "attos-mouse driver and ring menu";
      exec = "${pkg}/bin/attos-mouse daemon";
      restartSec = 1;
    };
    wayland.windowManager.hyprland.settings.layer_rule = lib.mkDefault [
      {
        match.namespace = "^attos-mouse$";
        blur = true;
        ignore_alpha = 0.3;
        no_anim = true;
      }
    ];
  };
}
