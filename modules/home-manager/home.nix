{
  config,
  lib,
  pkgs,
  ...
}:
let
  install = "${pkgs.coreutils}/bin/install";
in
{
  # Helpers shared by the feature home.nix files, reached as `config.lib.attos.<name>`
  # (Home Manager's `lib` option; `_module.args` would recurse through the freeform type).
  config.lib.attos = {
    # Seed config files that the app rewrites in place (store symlinks would be read-only).
    # `files` maps xdg.configFile names to null (the entry is a file) or to the file names
    # copied from the entry's directory. Files are copied 0600 only when missing, so the
    # app keeps its own changes; delete the file to receive new declared contents.
    mutableXdgConfigFiles =
      {
        name,
        files,
      }:
      let
        configHome = config.xdg.configHome;
        copy =
          entry: file:
          let
            source = config.xdg.configFile.${entry}.source;
            src = if file == null then source else "${source}/${file}";
            dst = if file == null then "${configHome}/${entry}" else "${configHome}/${entry}/${file}";
          in
          ''
            run ${install} -d -m 700 ${lib.escapeShellArg (dirOf dst)}
            [ -e ${lib.escapeShellArg dst} ] || run ${install} -m 600 ${src} ${lib.escapeShellArg dst}
          '';
        script = lib.concatStrings (
          lib.mapAttrsToList (
            entry: value: if value == null then copy entry null else lib.concatMapStrings (copy entry) value
          ) files
        );
      in
      {
        xdg.configFile = lib.mapAttrs (_: _: { enable = false; }) files;
        home.activation."install-${name}-config" = lib.hm.dag.entryAfter [ "linkGeneration" ] script;
      };

    # Requisite keeps restarts after logout from starting the app (and its fcitx5 dependency) outside a graphical session.
    graphicalAppService =
      {
        description,
        exec,
        wantsFcitx ? false,
        restart ? "on-failure",
        restartSec ? null,
        killMode ? null,
      }:
      {
        Unit = {
          Description = description;
          PartOf = [ "graphical-session.target" ];
          Requisite = [ "graphical-session.target" ];
          Wants = lib.optional wantsFcitx "fcitx5-daemon.service";
          After = [ "graphical-session.target" ] ++ lib.optional wantsFcitx "fcitx5-daemon.service";
        };
        Service = {
          ExecStart = exec;
          Restart = restart;
        }
        // lib.optionalAttrs (restartSec != null) { RestartSec = restartSec; }
        // lib.optionalAttrs (killMode != null) { KillMode = lib.mkDefault killMode; };
        Install.WantedBy = [ "graphical-session.target" ];
      };
  };
}
