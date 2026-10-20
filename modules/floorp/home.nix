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
      package = pkgs.floorp-bin;

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

        Sync = {
          Enabled = true;
          Addons = true;
          Bookmarks = true;
          History = true;
          OpenTabs = true;
          Settings = true;
          Passwords = false;
          Addresses = false;
          PaymentMethods = false;
          Locked = false;
        };

        Preferences = {
          "identity.fxaccounts.enabled" = {
            Value = true;
            Status = "default";
          };

          "services.sync.engine.addons" = {
            Value = true;
            Status = "default";
          };

          "services.sync.engine.bookmarks" = {
            Value = true;
            Status = "default";
          };

          "services.sync.engine.history" = {
            Value = true;
            Status = "default";
          };

          "services.sync.engine.prefs" = {
            Value = true;
            Status = "default";
          };

          "services.sync.engine.tabs" = {
            Value = true;
            Status = "default";
          };

          "services.sync.engine.passwords" = {
            Value = false;
            Status = "default";
          };

          "services.sync.engine.addresses" = {
            Value = false;
            Status = "default";
          };

          "services.sync.engine.creditcards" = {
            Value = false;
            Status = "default";
          };

          "sidebar.revamp" = {
            Value = true;
            Status = "default";
          };

          "sidebar.verticalTabs" = {
            Value = true;
            Status = "default";
          };

          "floorp.mousegesture.enabled" = {
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
