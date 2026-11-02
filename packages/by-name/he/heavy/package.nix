{ build-go-program }:
build-go-program {
  pname = "heavy";
  src = ./.;
  meta.description = "Serialize memory-heavy commands per host and dispatch them to a larger host";
}
