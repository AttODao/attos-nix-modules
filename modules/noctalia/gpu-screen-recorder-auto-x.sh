set -euo pipefail

actual_gpu_screen_recorder=@GPU_SCREEN_RECORDER@
recording_to_x=@RECORDING_TO_X@

args=("$@")
output_path=""
i=0
while [ "$i" -lt "$#" ]; do
  arg="${args[$i]}"
  case "$arg" in
    -o|--output)
      next_index=$((i + 1))
      if [ "$next_index" -lt "$#" ]; then
        output_path="${args[$next_index]}"
      fi
      break
      ;;
    -o=*|--output=*)
      output_path="${arg#*=}"
      break
      ;;
  esac
  i=$((i + 1))
done

marker="$(mktemp)"
trap 'rm -f "$marker"' EXIT

set +e
"$actual_gpu_screen_recorder" "$@"
status=$?
set -e

if [ "$status" -eq 0 ]; then
  if [ -n "$output_path" ] && [ -f "$output_path" ]; then
    log_path="${output_path%.*}-x.log"
    nohup "$recording_to_x" "$output_path" >"$log_path" 2>&1 </dev/null &
  else
    newest_recording=""
    for candidate in @RECORDINGS_DIRECTORY@/*.mp4; do
      [ -e "$candidate" ] || continue
      case "$candidate" in
        *-x.mp4) continue ;;
      esac
      if [ "$candidate" -nt "$marker" ]; then
        if [ -z "$newest_recording" ] || [ "$candidate" -nt "$newest_recording" ]; then
          newest_recording="$candidate"
        fi
      fi
    done

    if [ -n "$newest_recording" ]; then
      log_path="${newest_recording%.*}-x.log"
      nohup "$recording_to_x" "$newest_recording" >"$log_path" 2>&1 </dev/null &
    fi
  fi
fi

exit "$status"
