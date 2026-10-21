{ lib, ps, ... }:
{
  imports = [ ./nixos.nix ];

  options.modules.login-pin = {
    enable = lib.mkEnableOption "6-digit PIN authentication for one account on greetd and TTY login";
    user = lib.mkOption {
      type = lib.types.nullOr lib.types.nonEmptyStr;
      default = null;
      description = "Only account that may log in with a PIN; required when enabled. Other users skip the PIN prompt and authenticate with their password.";
    };
    pinDatabaseFile = ps.pathOption "Absolute runtime path of the pam_userdb database (ending in .db); required when enabled. Supply a decrypted secret, or point at /etc/security/login-pin/pins.db to manage it on the host with the installed set-login-pin command.";
  };
}
