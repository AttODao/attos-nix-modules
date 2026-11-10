{
  osConfig,
  lib,
  pkgs,
  ...
}:
let
  cfg = osConfig.modules.floorp;
in
{
  config = lib.mkIf cfg.enable {
    programs.floorp = {
      enable = true;
      # Floorp の policy が拒否する設定は autoconfig の既定値で渡す。
      package = lib.mkDefault (
        pkgs.floorp-bin.override {
          extraPrefs = lib.concatStringsSep "\n" (
            lib.mapAttrsToList (
              name: value: "defaultPref(${builtins.toJSON name}, ${builtins.toJSON value});"
            ) cfg.defaultPreferences
          );
        }
      );

      policies = lib.mapAttrsRecursive (_: lib.mkDefault) (
        {
          OfferToSaveLogins = false;
          PasswordManagerEnabled = false;
          AutofillAddressEnabled = false;
          AutofillCreditCardEnabled = false;

          SearchEngines.Default = "DuckDuckGo";

          Preferences = {
            "sidebar.revamp" = {
              Value = true;
              Status = "default";
            };

            "sidebar.verticalTabs" = {
              Value = true;
              Status = "default";
            };
          };

          ExtensionSettings = lib.mapAttrs (_: url: {
            installation_mode = "normal_installed";
            install_url = url;
          }) cfg.extensions;
        }
        // lib.optionalAttrs (cfg.vaultwardenUrl != null) {
          "3rdparty".Extensions."{446900e4-71c2-419f-a6a7-df9c091e268b}".environment.base =
            cfg.vaultwardenUrl;
        }
      );
    };
  };
}
