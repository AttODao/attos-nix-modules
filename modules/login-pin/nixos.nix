{
  config,
  lib,
  pkgs,
  attopkgs,
  ...
}:

let
  cfg = config.modules.login-pin;
  loginPinSecret = config.sops.secrets."login-pin/pins.db" or null;
  loginPinDatabase = if loginPinSecret == null then "/etc/security/login-pin/pins.db" else loginPinSecret.path;

  setLoginPin =
    pkgs.runCommand "set-login-pin"
      {
        nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
        meta.mainProgram = "set-login-pin";
      }
      ''
        makeBinaryWrapper ${lib.getExe attopkgs.login-pin} $out/bin/set-login-pin \
          --add-flag set \
          --prefix PATH : ${
            lib.makeBinPath [
              pkgs.coreutils
              pkgs.mkpasswd
              (lib.getBin pkgs.db4)
            ]
          }
      '';

  pinPamFor =
    serviceName:
    let
      authRules = config.security.pam.services.${serviceName}.rules.auth;
      authRuleName =
        if authRules ? unix then
          "unix"
        else if authRules ? login then
          "login"
        else
          throw "login-pin: '${serviceName}' has no unix or login PAM auth rule to precede";
    in
    {
      unixAuth = true;

      # greetd delegates to login, while direct services authenticate through pam_unix.
      # pam_userdb stores the prompted PIN as PAM_AUTHTOK, which pam_unix try_first_pass reuses.
      rules.auth.login-pin = {
        order = authRules.${authRuleName}.order - 10;
        control = "sufficient";
        modulePath = "${config.security.pam.package}/lib/security/pam_userdb.so";
        args = [
          # pam_userdb appends ".db" to this path.
          "db=${lib.removeSuffix ".db" loginPinDatabase}"
          "crypt=crypt"
        ];
      };
    };
in
{
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.hasSuffix ".db" loginPinDatabase;
        message = "modules.login-pin: sops.secrets.\"login-pin/pins.db\".path must end in .db for pam_userdb.";
      }
    ];

    environment.systemPackages = lib.optional (loginPinSecret == null) setLoginPin;

    system.activationScripts = lib.mkIf (loginPinSecret == null) {
      loginPinDir = ''
        install -d -m 0700 -o root -g root /etc/security/login-pin
      '';
    };

    security.pam.services = lib.genAttrs [ "greetd" "login" ] pinPamFor;
  };
}
