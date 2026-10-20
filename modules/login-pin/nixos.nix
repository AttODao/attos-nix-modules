{
  config,
  lib,
  pkgs,
  attopkgs,
  ...
}:

let
  cfg = config.modules.login-pin;
  ps = import ../public-services/lib.nix { inherit lib; };
  user = ps.require "modules.login-pin" "user" cfg.user;
  loginPinDatabase = ps.require "modules.login-pin" "pinDatabaseFile" cfg.pinDatabaseFile;
  # set-login-pin writes here; a consumer-supplied database elsewhere is read-only for the host.
  helperDatabase = "/etc/security/login-pin/pins.db";
  hostManaged = loginPinDatabase == helperDatabase;
  pamModule = name: "${config.security.pam.package}/lib/security/${name}.so";
  faillockArgs = [
    "deny=5"
    "unlock_time=300"
  ];

  setLoginPin =
    pkgs.runCommand "set-login-pin"
      {
        nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
        meta.mainProgram = "set-login-pin";
      }
      ''
        makeBinaryWrapper ${lib.getExe attopkgs.login-pin} $out/bin/set-login-pin \
          --add-flag set \
          --set LOGIN_PIN_USER ${lib.escapeShellArg user} \
          --prefix PATH : ${
            lib.makeBinPath [
              pkgs.coreutils
              pkgs.mkpasswd
              (lib.getBin pkgs.db4)
            ]
          }
      '';

  # greetd's PAM service substacks/includes `login`, so one stack covers greetd and the TTY.
  loginRules = config.security.pam.services.login.rules;
  base = loginRules.auth.unix.order;
  denyOrder = loginRules.auth.deny.order;
  loginPinPam = {
    unixAuth = true;

    # pam_userdb stores the prompted PIN as PAM_AUTHTOK, which pam_unix try_first_pass reuses.
    rules.auth = {
      # Lock the account after repeated failures; the account rule below resets the tally on success.
      login-pin-faillock-preauth = {
        order = base - 50;
        control = "required";
        modulePath = pamModule "pam_faillock";
        args = [ "preauth" ] ++ faillockArgs;
      };
      # A six-digit PIN is brute-forceable; delay every failed attempt.
      # Not security.pam.services.<name>.failDelay: it adds an early pam_unix that prompts for the password before the PIN.
      login-pin-faildelay = {
        order = base - 40;
        control = "optional";
        modulePath = pamModule "pam_faildelay";
        args = [ "delay=3000000" ];
      };
      # Only the configured account sees the PIN prompt; others skip it (the next rule) and use pam_unix.
      login-pin-user = {
        order = base - 20;
        control = "[success=ok default=1]";
        modulePath = pamModule "pam_succeed_if";
        args = [
          "quiet"
          "user"
          "="
          user
        ];
      };
      login-pin = {
        order = base - 10;
        control = "sufficient";
        modulePath = pamModule "pam_userdb";
        args = [
          # pam_userdb appends ".db" to this path.
          "db=${lib.removeSuffix ".db" loginPinDatabase}"
          "crypt=crypt"
        ];
      };
      # Reached only when every authentication module failed: record the failure before pam_deny.
      login-pin-faillock-authfail = {
        order = denyOrder - 1;
        control = "[default=die]";
        modulePath = pamModule "pam_faillock";
        args = [ "authfail" ] ++ faillockArgs;
      };
    };
    rules.account.login-pin-faillock = {
      order = loginRules.account.unix.order + 1;
      control = "required";
      modulePath = pamModule "pam_faillock";
    };
  };
in
{
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.user != null && cfg.pinDatabaseFile != null;
        message = "modules.login-pin.user and pinDatabaseFile are required when enabled.";
      }
      {
        assertion = cfg.pinDatabaseFile == null || lib.hasSuffix ".db" cfg.pinDatabaseFile;
        message = "modules.login-pin.pinDatabaseFile must end in .db for pam_userdb.";
      }
    ];

    environment.systemPackages = lib.optional hostManaged setLoginPin;

    system.activationScripts = lib.mkIf hostManaged {
      loginPinDir = ''
        install -d -m 0700 -o root -g root ${builtins.dirOf helperDatabase}
      '';
    };

    security.pam.services.login = loginPinPam;
  };
}
