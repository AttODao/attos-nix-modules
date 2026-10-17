{
  lib,
  buildGoModule,
}:

buildGoModule {
  pname = "atcoder-go";
  version = "0.2.0";
  src = ../cli;
  vendorHash = null;

  meta = {
    description = "AtCoder Go project, contest, test, submission and snippet commands";
    license = lib.licenses.mit;
    mainProgram = "atcoder-go";
  };
}
