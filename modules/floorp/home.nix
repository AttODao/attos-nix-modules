{
  osConfig,
  config,
  lib,
  pkgs,
  ...
}:
{
  config = lib.mkIf osConfig.modules.floorp.enable {
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

        "3rdparty".Extensions."{446900e4-71c2-419f-a6a7-df9c091e268b}".environment = {
          base = "https://vaultwarden.attodao.cc";
        };

        ExtensionSettings = {
          "firefox@ghostery.com" = {
            installation_mode = "force_installed";
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/ghostery/latest.xpi";
          };

          "{446900e4-71c2-419f-a6a7-df9c091e268b}" = {
            installation_mode = "force_installed";
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/bitwarden-password-manager/latest.xpi";
          };

          "{3c6bf0cc-3ae2-42fb-9993-0d33104fdcaf}" = {
            installation_mode = "force_installed";
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/youtube-addon/latest.xpi";
          };

          "jid1-q4sG8pYhq8KGHs@jetpack" = {
            installation_mode = "force_installed";
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/adblock-for-youtube/latest.xpi";
          };

          "{0d7cafdd-501c-49ca-8ebb-e3341caaa55e}" = {
            installation_mode = "force_installed";
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/youtube-nonstop/latest.xpi";
          };

          "opd_release@kwdev" = {
            installation_mode = "force_installed";
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/open-deck/latest.xpi";
          };

          "{71e91189-9cd2-4e46-895d-bcc38f0053c4}" = {
            installation_mode = "force_installed";
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/ttv-ab-twitch-ad-blocker/latest.xpi";
          };
        };
      };
    };
  };
}
