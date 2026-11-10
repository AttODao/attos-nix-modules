{
  osConfig,
  lib,
  pkgs,
  ...
}:
let
  cfg = osConfig.modules.thunderbird;
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
  config = lib.mkIf cfg.enable {
    programs.thunderbird = {
      enable = true;
      package = lib.mkDefault pkgs.thunderbird-esr;
      languagePacks = [ "ja" ];

      profiles.${cfg.profile} = {
        isDefault = true;
        settings = lib.mapAttrs (_: lib.mkDefault) {
          # Lets the bundled add-on run without enabling it by hand.
          "extensions.autoDisableScopes" = 0;
          "mail.shell.checkDefaultClient" = false;
          "mailnews.start_page.enabled" = false;
        };
        extensions = [ thunderbirdMinimizeOnStartupAddon ];
      };
    };

    # Consumer-declared accounts; each is wired to Thunderbird unless the consumer says otherwise.
    accounts.email.accounts = lib.mapAttrs (
      _: account:
      account
      // {
        thunderbird = {
          enable = lib.mkDefault true;
        }
        // (account.thunderbird or { });
      }
    ) cfg.accounts;
  };
}
