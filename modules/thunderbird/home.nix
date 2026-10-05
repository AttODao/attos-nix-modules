{
  osConfig,
  config,
  lib,
  pkgs,
  ...
}:
let
  thunderbirdMinimizeOnStartupAddon = pkgs.runCommandLocal "thunderbird-minimize-on-startup" { } ''
    install -Dm444 ${
      pkgs.fetchurl {
        url = "https://addons.thunderbird.net/thunderbird/downloads/file/1030065/minimize_on_startup-1.1-tb.xpi?src=search";
        hash = "sha256-Q6YeL6JSFQDy3Vt8WbIIoEI6paJ1uzgejVskwaujQb0=";
      }
    } \
      "$out/share/mozilla/extensions/{ec8030f7-c20a-464f-9b0e-13a3a9e97384}/mas@aandrzej.com.xpi"
  '';
in
{
  config = lib.mkIf osConfig.modules.thunderbird.enable {
    programs.thunderbird = {
      enable = true;
      package = pkgs.thunderbird-esr;
      languagePacks = [ "ja" ];

      profiles.attodao = {
        isDefault = true;
        accountsOrder = [
          "attodao"
          "gmail"
        ];
        settings = {
          "extensions.autoDisableScopes" = 0;
          "mail.shell.checkDefaultClient" = false;
          "mail.spellcheck.inline" = true;
          "mailnews.start_page.enabled" = false;
        };
        extensions = [ thunderbirdMinimizeOnStartupAddon ];
      };
    };

    accounts = {
      calendar.basePath = ".local/share/calendars";

      email.accounts = {
        attodao = {
          primary = true;
          address = "attodao@attodao.cc";
          realName = "AttODao";
          userName = "attodao@attodao.cc";

          imap = {
            host = "mail.attodao.cc";
            port = 993;
            authentication = "plain";
            tls.enable = true;
          };

          smtp = {
            host = "mail.attodao.cc";
            port = 587;
            authentication = "plain";
            tls = {
              enable = true;
              useStartTls = true;
            };
          };

          thunderbird.enable = true;
        };

        gmail = {
          address = "atsuatat@gmail.com";
          realName = "AttODao";
          flavor = "gmail.com";
          thunderbird.enable = true;
        };
      };
    };
  };
}
