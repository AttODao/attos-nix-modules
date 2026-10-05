if ! @docker@ network inspect immich >/dev/null 2>&1; then
  @docker@ network create immich >/dev/null 2>&1 \
    || @docker@ network inspect immich >/dev/null
fi
