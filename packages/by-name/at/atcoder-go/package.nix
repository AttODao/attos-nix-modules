# project scaffoldのdevenvと同じsourceをホスト用に構築する。
{ build-go-program }:
build-go-program {
  pname = "atcoder-go";
  src = ../../../../modules/atcoder-go/assets/atcoder/cli;
  meta.description = "AtCoder Go project, contest, test, submission and snippet commands";
}
