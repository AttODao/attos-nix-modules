{ build-go-program }:
build-go-program {
  pname = "wireguard-runtime";
  src = ./.;
  meta.description = "Runtime WireGuard client configuration and QR generation for the wireguard-server module";
}
