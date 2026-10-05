if ! @docker@ network inspect @network@ >/dev/null 2>&1; then
  @docker@ network create @network@ >/dev/null 2>&1 \
    || @docker@ network inspect @network@ >/dev/null
fi
