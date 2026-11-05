{ build-go-program }:
build-go-program {
  pname = "attos-jobs";
  src = ./.;
  meta.description = "List and stop work that other hosts run on this machine";
}
