set -euo pipefail

recordings_directory=@RECORDINGS_DIRECTORY@
input_path="${1:-}"

if [ -z "$input_path" ]; then
  recordings=()
  for candidate in "$recordings_directory"/*.mp4; do
    [ -e "$candidate" ] || continue
    case "$candidate" in
      *-x.mp4) continue ;;
    esac
    recordings+=( "$candidate" )
  done

  if [ "${#recordings[@]}" -eq 0 ]; then
    for candidate in "$recordings_directory"/*.mp4; do
      [ -e "$candidate" ] || continue
      recordings+=( "$candidate" )
    done
  fi

  if [ "${#recordings[@]}" -eq 0 ]; then
    printf 'recording-to-x: no MP4 recordings found in %s\n' "$recordings_directory" >&2
    exit 1
  fi

  input_path="${recordings[0]}"
  for candidate in "${recordings[@]:1}"; do
    if [ "$candidate" -nt "$input_path" ]; then
      input_path="$candidate"
    fi
  done
fi

if [ ! -f "$input_path" ]; then
  printf 'recording-to-x: input file not found: %s\n' "$input_path" >&2
  exit 1
fi

output_path="${2:-${input_path%.*}-x.mp4}"
output_dir="$(dirname -- "$output_path")"
mkdir -p "$output_dir"

# Tone map HDR to SDR and drop HDR side data before encoding for X.
tone_map_filter='zscale=transfer=linear,format=gbrpf32le,tonemap=tonemap=mobius:desat=0,sidedata=mode=delete,zscale=transfer=bt709:matrix=bt709:primaries=bt709:range=tv,scale=1280:720:force_original_aspect_ratio=decrease:flags=lanczos,pad=1280:720:(ow-iw)/2:(oh-ih)/2:color=black,setsar=1,format=yuv420p'
tmp_output="$(mktemp --tmpdir="$output_dir" "$(basename -- "$output_path" .mp4).XXXXXX.mp4")"
trap 'rm -f "$tmp_output"' EXIT

ffmpeg -hide_banner -y -i "$input_path" \
  -map 0:v:0 -map 0:a:0? -map_metadata 0 -map_chapters 0 \
  -vf "$tone_map_filter" \
  -c:v libx264 -preset slow -crf 18 -profile:v high -pix_fmt yuv420p \
  -color_primaries bt709 -color_trc bt709 -colorspace bt709 \
  -c:a aac -b:a 160k -ar 48000 -ac 2 \
  -movflags +faststart \
  -f mp4 \
  "$tmp_output"

mv -f "$tmp_output" "$output_path"
trap - EXIT

printf 'Wrote %s\n' "$output_path"
