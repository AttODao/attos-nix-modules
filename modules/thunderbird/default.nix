{ config, lib, ... }:
{
  imports = [ ./nixos.nix ];

  options.modules.thunderbird = {
    enable = lib.mkEnableOption "shared Thunderbird configuration";
    profile = lib.mkOption {
      type = lib.types.strMatching "[A-Za-z0-9._-]+";
      default = "default";
      description = "Name of the default Thunderbird profile created for every Home Manager user.";
    };
    accounts = lib.mkOption {
      type = lib.types.attrsOf lib.types.raw;
      default = { };
      example = lib.literalExpression ''
        {
          work = {
            primary = true;
            address = "alice@example.org";
            realName = "Alice";
            userName = "alice@example.org";
            imap = { host = "mail.example.org"; port = 993; };
            smtp = { host = "mail.example.org"; port = 587; tls.useStartTls = true; };
          };
        }
      '';
      description = "Email accounts in Home Manager accounts.email.accounts shape, applied to every Home Manager user with thunderbird.enable defaulting to true. Exactly one account must set primary when any is declared; credentials stay in each user's Thunderbird profile.";
    };
  };

  config = lib.mkIf config.modules.thunderbird.enable {
    home-manager.sharedModules = [ ./home.nix ];
  };
}
