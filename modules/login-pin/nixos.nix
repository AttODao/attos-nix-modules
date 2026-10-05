{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.modules.login-pin;
  users = [ "attodao" ];
  allowedUsersJson = builtins.toJSON users;
  allowedUsersShell = lib.concatStringsSep " " users;
  loginPinSecret = config.sops.secrets."login-pin/attodao.pbkdf2" or null;
  loginPinHashDirectory =
    if loginPinSecret == null then "/etc/security/login-pin" else builtins.dirOf loginPinSecret.path;

  checkLoginPin = pkgs.writeTextFile {
    name = "check-login-pin";
    destination = "/bin/check-login-pin";
    executable = true;
    text =
      builtins.replaceStrings
        [
          "@PYTHON@"
          ''["@ALLOWED_USERS@"]''
          "@PIN_HASH_DIRECTORY@"
        ]
        [
          "${pkgs.python3}/bin/python3"
          allowedUsersJson
          loginPinHashDirectory
        ]
        (builtins.readFile ./check-login-pin.py);
  };

  setLoginPin = pkgs.writeShellApplication {
    name = "set-login-pin";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.python3
    ];

    text = builtins.replaceStrings [ "@ALLOWED_USERS@" ] [ allowedUsersShell ] (
      builtins.readFile ./set-login-pin.sh
    );
  };

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
      rules.auth.login-pin = {
        order = authRules.${authRuleName}.order - 10;
        control = "sufficient";
        modulePath = "${config.security.pam.package}/lib/security/pam_exec.so";
        args = [
          "quiet"
          "expose_authtok"
          "${checkLoginPin}/bin/check-login-pin"
        ];
      };
    };
in
{
  config = lib.mkIf cfg.enable {
    environment.systemPackages = lib.optional (loginPinSecret == null) setLoginPin;

    system.activationScripts = lib.mkIf (loginPinSecret == null) {
      loginPinDir = ''
        install -d -m 0700 -o root -g root /etc/security/login-pin
      '';
    };

    security.pam.services = lib.genAttrs [ "greetd" "login" ] pinPamFor;
  };
}
