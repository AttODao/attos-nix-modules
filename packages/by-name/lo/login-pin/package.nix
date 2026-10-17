{
  lib,
  build-go-program,
  db4,
  mkpasswd,
}:
(build-go-program {
  pname = "login-pin";
  src = ./.;
  meta.description = "Login PIN database helper for pam_userdb (login-pin set)";
}).overrideAttrs
  {
    # The tests build a real pam_userdb database with the runtime tools.
    nativeCheckInputs = [
      (lib.getBin db4)
      mkpasswd
    ];
  }
