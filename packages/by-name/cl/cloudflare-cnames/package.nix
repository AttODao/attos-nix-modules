{ build-go-program }:
build-go-program {
  pname = "cloudflare-cnames";
  src = ./.;
  meta.description = "Sync declared Cloudflare CNAMEs, pruning only records carrying the ownership comment";
}
