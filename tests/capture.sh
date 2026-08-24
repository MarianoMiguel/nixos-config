#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
scratch=$(mktemp -d)
fake_bin="$scratch/bin"
state_dir="$scratch/state"
runtime_dir="$scratch/runtime"
pictures_dir="$scratch/Pictures/Screenshots"
videos_dir="$scratch/Videos/Recordings"
log_file="$scratch/commands.log"
active_file="$scratch/service-state"
clipboard_file="$scratch/clipboard"

cleanup() {
  rm -rf "$scratch"
}
trap cleanup EXIT

mkdir -p "$fake_bin"

cat > "$fake_bin/grim" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'grim' >> "$TEST_LOG"
printf ' %s' "$@" >> "$TEST_LOG"
printf '\n' >> "$TEST_LOG"
output=${!#}
printf 'PNG' > "$output"
EOF

cat > "$fake_bin/slurp" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "${TEST_SLURP_RESULT:?}"
EOF

cat > "$fake_bin/wl-copy" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
command cat > "$TEST_CLIPBOARD"
printf 'wl-copy' >> "$TEST_LOG"
printf ' %s' "$@" >> "$TEST_LOG"
printf '\n' >> "$TEST_LOG"
if [[ ${TEST_WL_COPY_HOLD:-0} == 1 ]]; then
  # wl-copy serves the clipboard from a detached child. Keep this test child
  # alive long enough to catch capture locks accidentally inherited from the
  # caller, while detaching its standard streams like the real provider.
  (sleep 2) </dev/null >/dev/null 2>&1 &
fi
EOF

cat > "$fake_bin/pactl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  get-default-sink)
    printf '%s\n' 'alsa_output.test.stereo'
    ;;
  'list short sources')
    printf '%s\n' '41 alsa_output.test.stereo.monitor PipeWire s32le 2ch 48000Hz RUNNING'
    ;;
  *)
    exit 1
    ;;
esac
EOF

cat > "$fake_bin/systemctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ ${1:-} == --user ]] && shift
case "${1:-}" in
  is-active)
    [[ $(command cat "$TEST_ACTIVE_FILE" 2>/dev/null || true) == active ]]
    ;;
  start)
    printf '%s\n' active > "$TEST_ACTIVE_FILE"
    printf 'systemctl start %s\n' "${2:-}" >> "$TEST_LOG"
    ;;
  stop)
    printf '%s\n' inactive > "$TEST_ACTIVE_FILE"
    printf 'systemctl stop %s\n' "${2:-}" >> "$TEST_LOG"
    ;;
  reset-failed|import-environment)
    printf 'systemctl %s\n' "$*" >> "$TEST_LOG"
    ;;
  *)
    printf 'unexpected systemctl invocation: %s\n' "$*" >&2
    exit 1
    ;;
esac
EOF

cat > "$fake_bin/notify-send" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'notify-send' >> "$TEST_LOG"
printf ' %s' "$@" >> "$TEST_LOG"
printf '\n' >> "$TEST_LOG"
for argument in "$@"; do
  if [[ $argument == --print-id ]]; then
    printf '%s\n' 42
  fi
done
EOF

cat > "$fake_bin/wf-recorder" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'wf-recorder' >> "$TEST_LOG"
printf ' %s' "$@" >> "$TEST_LOG"
printf '\n' >> "$TEST_LOG"
output=
while (($#)); do
  if [[ $1 == -f ]]; then
    shift
    output=${1:?missing recording output}
  fi
  shift
done
[[ -n $output ]]
printf 'VIDEO' > "$output"
EOF

cat > "$fake_bin/ffprobe" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
output=${!#}
[[ -s $output ]]
printf '%s\n' video
EOF

chmod +x "$fake_bin"/*

run_capture() {
  env \
    PATH="$fake_bin:$PATH" \
    HOME="$scratch/home" \
    XDG_RUNTIME_DIR="$scratch/xdg-runtime" \
    CAPTURE_STATE_DIR="$state_dir" \
    CAPTURE_RUNTIME_DIR="$runtime_dir" \
    CAPTURE_PICTURES_DIR="$pictures_dir" \
    CAPTURE_VIDEOS_DIR="$videos_dir" \
    CAPTURE_TIMESTAMP='2026-08-23 12-00-00' \
    TEST_LOG="$log_file" \
    TEST_ACTIVE_FILE="$active_file" \
    TEST_CLIPBOARD="$clipboard_file" \
    TEST_WL_COPY_HOLD="${TEST_WL_COPY_HOLD:-0}" \
    TEST_SLURP_RESULT="${TEST_SLURP_RESULT:-10,20 301x201}" \
    "$repo/scripts/capture.sh" "$@"
}

TEST_WL_COPY_HOLD=1 run_capture screenshot-full
full_screenshot="$pictures_dir/Screenshot 2026-08-23 12-00-00.png"
[[ -s $full_screenshot ]]
[[ $(cat "$clipboard_file") == PNG ]]
grep -Eq '^grim .*/\.capture-.*\.png$' "$log_file"
grep -Fq 'wl-copy --type image/png' "$log_file"
# Screenshots must not lock the recording state. The real wl-copy keeps a
# detached process alive, which used to inherit this lock and deadlock every
# later capture shortcut.
flock -n "$state_dir/control.lock" true

: > "$log_file"
run_capture screenshot-region
region_screenshot="$pictures_dir/Screenshot 2026-08-23 12-00-00-2.png"
[[ -s $region_screenshot ]]
grep -Eq '^grim --geometry 10,20 301x201 .*/\.capture-.*\.png$' "$log_file"

[[ $(run_capture audio-status) == off ]]
[[ $(run_capture audio-toggle) == on ]]
[[ $(run_capture audio-status) == on ]]

: > "$log_file"
run_capture video-toggle
jq -e '
  .geometry == "10,20 300x200"
  and .audio_device == "alsa_output.test.stereo.monitor"
  and (.output_file | endswith("Screen Recording 2026-08-23 12-00-00.mp4"))
' "$runtime_dir/recording.json" >/dev/null
grep -Fq 'systemctl start mariano-capture-video.service' "$log_file"
run_capture record-started
grep -Fq 'System audio is included' "$log_file"
[[ $(cat "$runtime_dir/notification-id") == 42 ]]

run_capture record-service
video_file=$(jq -r '.output_file' "$runtime_dir/recording.json")
[[ -s $video_file ]]
grep -Fq 'wf-recorder --geometry 10,20 300x200' "$log_file"
grep -Fq -- "-f $video_file" "$log_file"
grep -Fq -- '--audio=alsa_output.test.stereo.monitor' "$log_file"
grep -Fq -- '--audio-codec=aac' "$log_file"

run_capture video-toggle
grep -Fq 'systemctl stop mariano-capture-video.service' "$log_file"
run_capture record-finished
grep -Fq 'Recording saved' "$log_file"
grep -Fq -- '--replace-id=42' "$log_file"
[[ ! -e $runtime_dir/notification-id ]]

: > "$video_file"
run_capture record-finished
grep -Fq 'Recording failed' "$log_file"

[[ $(run_capture audio-toggle) == off ]]

printf 'Capture behavior passed.\n'
