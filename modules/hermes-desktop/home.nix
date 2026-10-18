{
  osConfig,
  lib,
  attopkgs,
  ...
}:
let
  cfg = osConfig.modules.hermes-desktop;
  # 初回だけremote接続を書く。既存の接続設定・session・tokenはappの状態として保持する。
  initialConnection = builtins.toJSON {
    mode = "remote";
    remote = {
      inherit (cfg) url;
      authMode = "oauth";
    };
  };
in
{
  config = lib.mkIf cfg.enable {
    home.packages = [
      (attopkgs.hermes-desktop.override {
        extraRun = [
          ''
            hermes_desktop_config="''${XDG_CONFIG_HOME:-$HOME/.config}/Hermes/connection.json"
            if [ ! -e "$hermes_desktop_config" ]; then
              mkdir -p "''${hermes_desktop_config%/*}"
              (umask 077 && printf '%s\n' ${lib.escapeShellArg initialConnection} > "$hermes_desktop_config")
            fi
          ''
        ];
      })
    ];
  };
}
