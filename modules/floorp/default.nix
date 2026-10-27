{ config, lib, ... }:
{
  options.modules.floorp = {
    enable = lib.mkEnableOption "shared Floorp configuration";
    defaultPreferences = lib.mkOption {
      type =
        with lib.types;
        attrsOf (oneOf [
          bool
          int
          str
        ]);
      default = {
        "services.sync.engine.passwords" = false;
        "floorp.mousegesture.enabled" = true;
      };
      description = "Preferences the enterprise policy cannot set, applied as defaultPref through autoconfig; users may change them. A consumer definition replaces the whole default set.";
    };
    vaultwardenUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.nonEmptyStr;
      default = null;
      example = "https://vault.example.org";
      description = "Self-hosted server preset for the Bitwarden extension; null leaves the extension's environment untouched.";
    };
    extensions = lib.mkOption {
      type = lib.types.attrsOf lib.types.nonEmptyStr;
      default = {
        "firefox@ghostery.com" = "https://addons.mozilla.org/firefox/downloads/latest/ghostery/latest.xpi";
        "{446900e4-71c2-419f-a6a7-df9c091e268b}" =
          "https://addons.mozilla.org/firefox/downloads/latest/bitwarden-password-manager/latest.xpi";
        "{3c6bf0cc-3ae2-42fb-9993-0d33104fdcaf}" =
          "https://addons.mozilla.org/firefox/downloads/latest/youtube-addon/latest.xpi";
        "jid1-q4sG8pYhq8KGHs@jetpack" =
          "https://addons.mozilla.org/firefox/downloads/latest/adblock-for-youtube/latest.xpi";
        "{0d7cafdd-501c-49ca-8ebb-e3341caaa55e}" =
          "https://addons.mozilla.org/firefox/downloads/latest/youtube-nonstop/latest.xpi";
        "opd_release@kwdev" = "https://addons.mozilla.org/firefox/downloads/latest/open-deck/latest.xpi";
        "{71e91189-9cd2-4e46-895d-bcc38f0053c4}" =
          "https://addons.mozilla.org/firefox/downloads/latest/ttv-ab-twitch-ad-blocker/latest.xpi";
      };
      description = "Extension ID to install URL, installed by policy as normal_installed (users may disable them). A consumer definition replaces the whole default set.";
    };
  };

  config = lib.mkIf config.modules.floorp.enable {
    home-manager.sharedModules = [ ./home.nix ];
  };
}
