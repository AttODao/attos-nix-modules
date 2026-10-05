# nix-instantiate --eval --strict tests/floorp.nix \
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
  enabled = t.hmFor [ { modules.floorp.enable = true; } ];
  policies = enabled.programs.floorp.policies;
  bitwarden = "{446900e4-71c2-419f-a6a7-df9c091e268b}";
  invalid = builtins.tryEval (t.cfgFor [ { modules.floorp.enable = "yes"; } ]).modules.floorp.enable;
in
assert !base.modules.floorp.enable;
assert !base.home-manager.users.test.programs.floorp.enable;
assert enabled.programs.floorp.enable;
assert enabled.programs.floorp.package == pkgs.floorp-bin;
assert builtins.elem enabled.programs.floorp.finalPackage enabled.home.packages;
assert !policies.DisableFirefoxAccounts;
assert !policies.OfferToSaveLogins && !policies.PasswordManagerEnabled;
assert !policies.AutofillAddressEnabled && !policies.AutofillCreditCardEnabled;
assert
  policies.SearchEngines == {
    Default = "DuckDuckGo";
    PreventInstalls = false;
  };
assert
  policies.Sync.Enabled && policies.Sync.Addons && policies.Sync.Bookmarks && policies.Sync.History;
assert !policies.Sync.Passwords && !policies.Sync.Addresses && !policies.Sync.PaymentMethods;
assert
  policies."3rdparty".Extensions.${bitwarden}.environment.base == "https://vaultwarden.attodao.cc";
assert
  builtins.attrNames policies.ExtensionSettings == [
    "firefox@ghostery.com"
    "jid1-q4sG8pYhq8KGHs@jetpack"
    "opd_release@kwdev"
    "{0d7cafdd-501c-49ca-8ebb-e3341caaa55e}"
    "{3c6bf0cc-3ae2-42fb-9993-0d33104fdcaf}"
    "{446900e4-71c2-419f-a6a7-df9c091e268b}"
    "{71e91189-9cd2-4e46-895d-bcc38f0053c4}"
  ];
assert lib.all (
  extension:
  extension.installation_mode == "force_installed"
  && lib.hasPrefix "https://addons.mozilla.org/firefox/downloads/latest/" extension.install_url
  && lib.hasSuffix "/latest.xpi" extension.install_url
) (builtins.attrValues policies.ExtensionSettings);
assert lib.hasSuffix ".drv" enabled.home.activationPackage.drvPath;
assert !invalid.success;
true
