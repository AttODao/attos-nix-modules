# nix-instantiate --eval --strict tests/thunderbird.nix \
#   --arg nixpkgs /path/to/nixpkgs --arg homeManager /path/to/home-manager
{
  nixpkgs,
  homeManager,
  system ? builtins.currentSystem,
}:
let
  t = import ./lib.nix { inherit nixpkgs homeManager system; };
  inherit (t) pkgs lib;
  base = t.cfgFor [ ];
  enabledCfg = t.cfgFor [ { modules.thunderbird.enable = true; } ];
  enabled = t.hm enabledCfg "test";
  profile = enabled.programs.thunderbird.profiles.attodao;
  account = enabled.accounts.email.accounts.attodao;
in
assert !base.modules.thunderbird.enable;
assert !base.home-manager.users.test.programs.thunderbird.enable;
assert !base.services.gnome.evolution-data-server.enable;
assert !base.services.gnome.gnome-keyring.enable;
assert enabled.programs.thunderbird.enable;
assert enabled.programs.thunderbird.package == pkgs.thunderbird-esr;
assert enabled.programs.thunderbird.languagePacks == [ "ja" ];
assert profile.isDefault;
assert
  profile.accountsOrder == [
    "attodao"
    "gmail"
  ];
assert profile.settings."extensions.autoDisableScopes" == 0;
assert !profile.settings."mail.shell.checkDefaultClient";
assert profile.settings."mail.spellcheck.inline";
assert !profile.settings."mailnews.start_page.enabled";
assert builtins.length profile.extensions == 1;
assert (builtins.head profile.extensions).name == "thunderbird-minimize-on-startup";
assert enabled.accounts.calendar.basePath == "/home/test/.local/share/calendars";
assert account.primary;
assert account.address == "attodao@attodao.cc";
assert account.realName == "AttODao";
assert account.userName == "attodao@attodao.cc";
assert account.imap.host == "mail.attodao.cc" && account.imap.port == 993;
assert account.imap.authentication == "plain" && account.imap.tls.enable;
assert account.smtp.host == "mail.attodao.cc" && account.smtp.port == 587;
assert
  account.smtp.authentication == "plain" && account.smtp.tls.enable && account.smtp.tls.useStartTls;
assert account.thunderbird.enable;
assert enabled.accounts.email.accounts.gmail.address == "atsuatat@gmail.com";
assert enabled.accounts.email.accounts.gmail.flavor == "gmail.com";
assert enabled.accounts.email.accounts.gmail.thunderbird.enable;
assert enabledCfg.services.gnome.evolution-data-server.enable;
assert enabledCfg.services.gnome.gnome-keyring.enable;
assert lib.hasSuffix ".drv" enabled.home.activationPackage.drvPath;
true
