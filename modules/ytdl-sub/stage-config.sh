set -euo pipefail

# Validate every input before replacing configuration. Never copy cookies or
# remove media, archives, history, working data, or unrelated config files.
for source in "$YTDL_SUB_CONFIG_FILE" "$YTDL_SUB_YOUTUBE_FILE" "$YTDL_SUB_TWITCH_FILE" "$YTDL_SUB_CRON_FILE" "$YTDL_SUB_COOKIE_FILE"; do
  if [ ! -f "$source" ] || [ ! -r "$source" ]; then
    printf 'ytdl-sub: required input file is not readable: %s\n' "$source" >&2
    exit 1
  fi
done

config_root="$YTDL_SUB_DATA_DIR/config"
install -d -m 0700 -o "$YTDL_SUB_UID" -g "$YTDL_SUB_GID" -- "$config_root"
# These two obsolete generated files are the only legacy cleanup.
rm -f -- "$config_root/config-twitch.yaml" "$config_root/subscriptions.yaml"
install -m 0644 -o "$YTDL_SUB_UID" -g "$YTDL_SUB_GID" -- "$YTDL_SUB_CONFIG_FILE" "$config_root/config.yaml"
install -m 0644 -o "$YTDL_SUB_UID" -g "$YTDL_SUB_GID" -- "$YTDL_SUB_YOUTUBE_FILE" "$config_root/subscriptions-youtube.yaml"
install -m 0644 -o "$YTDL_SUB_UID" -g "$YTDL_SUB_GID" -- "$YTDL_SUB_TWITCH_FILE" "$config_root/subscriptions-twitch.yaml"
install -m 0755 -o "$YTDL_SUB_UID" -g "$YTDL_SUB_GID" -- "$YTDL_SUB_CRON_FILE" "$config_root/cron"
