{
  osConfig,
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.discord;
  settingsFile = "${config.xdg.configHome}/${cfg.configName}/settings.json";
  managedSettings = (pkgs.formats.json { }).generate "discord-settings" cfg.settings;
  jq = lib.getExe pkgs.jq;
in
{
  config = lib.mkIf osConfig.modules.discord.enable {
    programs.discord = {
      enable = true;
      package = lib.mkIf (osConfig.modules.discord.commandLineArgs != "") (
        lib.mkDefault (
          pkgs.discord.override {
            commandLineArgs = osConfig.modules.discord.commandLineArgs;
          }
        )
      );
    };

    # Discord rewrites settings.json with its own keys, replacing the read-only link from
    # programs.discord; the next activation then backs it up and fails once a backup exists.
    # Merge the declared keys into Discord's mutable file instead of linking it.
    home.file.${settingsFile}.enable = false;
    home.activation.discordSettings = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      settings=${lib.escapeShellArg settingsFile}
      run mkdir -p "$(dirname "$settings")"
      if [ -L "$settings" ]; then run rm "$settings"; fi
      if [ -s "$settings" ] && current=$(${jq} -e 'objects' "$settings" 2>/dev/null); then
        merged=$(printf '%s' "$current" | ${jq} --slurpfile managed ${managedSettings} '. * $managed[0]')
      else
        merged=$(${jq} . ${managedSettings})
      fi
      if [ "$merged" != "$(cat "$settings" 2>/dev/null)" ]; then
        if [ -n "''${DRY_RUN:-}" ]; then
          echo "would update $settings"
        else
          tmp=$(mktemp "$settings.XXXXXX")
          printf '%s\n' "$merged" > "$tmp"
          mv -f "$tmp" "$settings"
        fi
      fi
    '';

    systemd.user.services.discord = config.lib.attos.graphicalAppService {
      description = "Discord desktop client";
      exec = "${config.programs.discord.package}/bin/discord --start-minimized";
      wantsFcitx = true;
      restartSec = 3;
      killMode = osConfig.modules.discord.service.killMode;
    };
  };
}
