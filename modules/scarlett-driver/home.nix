{
  osConfig,
  config,
  lib,
  pkgs,
  attopkgs,
  ...
}:
let
  cfg = osConfig.modules.scarlett-driver;
  pkg = attopkgs.scarlett-driver;
  toml = (pkgs.formats.toml { }).generate "scarlett-driver-config.toml" cfg.settings;
  checked = pkgs.runCommand "scarlett-driver-config-checked.toml" { } ''
    ${pkg}/bin/scarlett-driver check-config ${toml}
    cp ${toml} "$out"
  '';
in
{
  config = lib.mkIf cfg.enable {
    home.packages = [ pkg ];
    xdg.configFile."scarlett-driver/config.toml".source = lib.mkDefault checked;
    # The control device is granted to the active seat (uaccess), so the daemon follows the
    # graphical session. It restores the saved device state on connect and autosaves changes.
    systemd.user.services.scarlett-driver =
      lib.recursiveUpdate
        (config.lib.attos.graphicalAppService {
          description = "Scarlett Solo state and PipeWire control daemon";
          exec = "${pkg}/bin/scarlett-driver daemon";
          restartSec = 2;
        })
        {
          Unit = {
            After = [
              "graphical-session.target"
              "pipewire.service"
              "wireplumber.service"
            ];
            X-Restart-Triggers = [ "${checked}" ];
          };
        };
  };
}
