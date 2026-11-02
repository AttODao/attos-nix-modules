{ build-go-program }:
build-go-program {
  pname = "strata-wake";
  src = ./.;
  meta.description = "On-demand Strata: gateway proxy with Wake-on-LAN and idle stop, and the owner's control API";
}
