{
  lib,
  buildGoModule,
}:

buildGoModule {
  pname = "atcoder-snippet";
  version = "0.1.1";
  src = ../snippet;
  vendorHash = null;

  meta = {
    description = "Combine Go library source files into an AtCoder submission";
    license = lib.licenses.mit;
    mainProgram = "atcoder-snippet";
  };
}
