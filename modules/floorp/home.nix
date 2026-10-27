{
  osConfig,
  config,
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
      package = pkgs.floorp-bin.override {
        extraPrefs = lib.concatStringsSep "\n" (
          lib.mapAttrsToList (
            name: value: "defaultPref(${builtins.toJSON name}, ${builtins.toJSON value});"
          ) cfg.defaultPreferences
        );
      };

      policies = {
        DisableFirefoxAccounts = false;
        OfferToSaveLogins = false;
        PasswordManagerEnabled = false;
        AutofillAddressEnabled = false;
        AutofillCreditCardEnabled = false;

        SearchEngines = {
          Default = "DuckDuckGo";
          PreventInstalls = false;
        };

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
      }
      // lib.optionalAttrs (cfg.vaultwardenUrl != null) {
        "3rdparty".Extensions."{446900e4-71c2-419f-a6a7-df9c091e268b}".environment = {
          base = cfg.vaultwardenUrl;
        };
      }
      // {
        ExtensionSettings = lib.mapAttrs (_: url: {
          installation_mode = "normal_installed";
          install_url = url;
        }) cfg.extensions;
      };
    };
  };
}
