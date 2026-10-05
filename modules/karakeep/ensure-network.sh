if ! @docker@ network inspect karakeep >/dev/null 2>&1; then
  @docker@ network create \
    --driver bridge \
    --subnet @subnet@ \
    --gateway @gateway@ \
    karakeep >/dev/null 2>&1 \
    || @docker@ network inspect karakeep >/dev/null
fi
