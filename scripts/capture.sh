#!/usr/bin/env bash
set -euo pipefail

umask 077

state_dir=${CAPTURE_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/nixos-config/capture}
runtime_dir=${CAPTURE_RUNTIME_DIR:-${XDG_RUNTIME_DIR:?XDG_RUNTIME_DIR is required}/mariano-capture}
pictures_dir=${CAPTURE_PICTURES_DIR:-$HOME/Pictures/Screenshots}
videos_dir=${CAPTURE_VIDEOS_DIR:-$HOME/Videos/Recordings}
unit=${CAPTURE_UNIT:-mariano-capture-video.service}
audio_file="$state_dir/system-audio"
lock_file="$state_dir/control.lock"
plan_file="$runtime_dir/recording.json"
notification_file="$runtime_dir/notification-id"

notify_user() {
  notify-send --app-name="Capture" --urgency=low "$@" >/dev/null 2>&1 || true
}

unique_path() {
  local directory=$1
  local prefix=$2
  local extension=$3
  local timestamp=${CAPTURE_TIMESTAMP:-$(date '+%Y-%m-%d %H-%M-%S')}
  local candidate="$directory/$prefix $timestamp.$extension"
  local suffix=2

  while [[ -e $candidate ]]; do
    candidate="$directory/$prefix $timestamp-$suffix.$extension"
    suffix=$((suffix + 1))
  done
  printf '%s\n' "$candidate"
}

audio_status() {
  if [[ -f $audio_file ]] && [[ $(<"$audio_file") == on ]]; then
    printf '%s\n' on
  else
    printf '%s\n' off
  fi
}

set_audio() {
  local value=$1
  local temporary

  temporary=$(mktemp "$state_dir/system-audio.XXXXXX")
  printf '%s\n' "$value" > "$temporary"
  chmod 0600 "$temporary"
  mv -f "$temporary" "$audio_file"
  printf '%s\n' "$value"
  if [[ $value == on ]]; then
    notify_user "System audio enabled" "New screen recordings will include desktop audio."
  else
    notify_user "System audio disabled" "New screen recordings will be silent."
  fi
}

select_region() {
  local geometry

  if ! geometry=$(slurp); then
    return 1
  fi
  [[ -n $geometry ]] || return 1
  printf '%s\n' "$geometry"
}

normalize_video_geometry() {
  local geometry=$1
  local x
  local y
  local width
  local height

  if [[ ! $geometry =~ ^(-?[0-9]+),(-?[0-9]+)[[:space:]]+([0-9]+)x([0-9]+)$ ]]; then
    notify_user "Capture failed" "The selected region was not valid."
    return 1
  fi
  x=${BASH_REMATCH[1]}
  y=${BASH_REMATCH[2]}
  width=${BASH_REMATCH[3]}
  height=${BASH_REMATCH[4]}
  width=$((width - width % 2))
  height=$((height - height % 2))
  if ((width < 2 || height < 2)); then
    notify_user "Capture failed" "The selected region is too small."
    return 1
  fi
  printf '%s,%s %sx%s\n' "$x" "$y" "$width" "$height"
}

capture_screenshot() {
  local mode=$1
  local geometry=
  local output
  local temporary
  local clipboard_message="Saved and copied to the clipboard."
  local notification_body

  if [[ $mode == region ]]; then
    geometry=$(select_region) || return 0
  fi
  output=$(unique_path "$pictures_dir" "Screenshot" png)
  temporary=$(mktemp "$pictures_dir/.capture-XXXXXX.png")

  if [[ $mode == region ]]; then
    if ! grim --geometry "$geometry" "$temporary"; then
      rm -f "$temporary"
      notify_user "Screenshot failed" "The selected region could not be captured."
      return 1
    fi
  elif ! grim "$temporary"; then
    rm -f "$temporary"
    notify_user "Screenshot failed" "The displays could not be captured."
    return 1
  fi

  chmod 0600 "$temporary"
  mv -f "$temporary" "$output"
  if ! wl-copy --type image/png < "$output"; then
    clipboard_message="Saved, but the clipboard was unavailable."
  fi
  printf -v notification_body '%s\n%s' "$clipboard_message" "$output"
  notify_user --icon="$output" "Screenshot saved" "$notification_body"
  printf '%s\n' "$output"
}

system_audio_device() {
  local sink
  local monitor

  if ! sink=$(LC_ALL=C pactl get-default-sink) || [[ -z $sink ]]; then
    notify_user "Recording not started" "The default audio output could not be found."
    return 1
  fi
  monitor="$sink.monitor"
  if ! LC_ALL=C pactl list short sources | awk '{print $2}' | grep -Fxq "$monitor"; then
    notify_user "Recording not started" "The monitor for the default audio output is unavailable."
    return 1
  fi
  printf '%s\n' "$monitor"
}

record_service() {
  local geometry
  local output
  local audio
  local -a audio_arguments=()

  if ! jq -e '
    (.geometry | type) == "string"
    and (.geometry | test("^-?[0-9]+,-?[0-9]+ [0-9]+x[0-9]+$"))
    and (.output_file | type) == "string"
    and ((.audio_device == null) or ((.audio_device | type) == "string"))
  ' "$plan_file" >/dev/null; then
    printf 'capture: invalid recording plan\n' >&2
    return 1
  fi

  geometry=$(jq -r '.geometry' "$plan_file")
  output=$(jq -r '.output_file' "$plan_file")
  audio=$(jq -r '.audio_device // empty' "$plan_file")
  if [[ -n $audio ]]; then
    audio_arguments+=("--audio=$audio" "--audio-codec=aac")
  fi

  exec wf-recorder \
    --geometry "$geometry" \
    -f "$output" \
    --codec=libx264 \
    --pixel-format=yuv420p \
    --framerate=60 \
    --codec-param preset=veryfast \
    --codec-param crf=23 \
    "${audio_arguments[@]}"
}

record_started() {
  local audio_label="System audio is off"
  local notification_id

  if ! jq -e '(.audio_device == null) or ((.audio_device | type) == "string")' \
    "$plan_file" >/dev/null 2>&1; then
    printf 'capture: invalid recording plan\n' >&2
    return 1
  fi
  if [[ $(jq -r '.audio_device // empty' "$plan_file") ]]; then
    audio_label="System audio is included"
  fi

  notification_id=$(notify-send --app-name="Capture" --urgency=normal --print-id \
    --expire-time=0 --icon=media-record \
    "Recording region" "$audio_label. Press Alt+Shift+5 again to stop." 2>/dev/null || true)
  if [[ $notification_id =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$notification_id" > "$notification_file"
    chmod 0600 "$notification_file"
  fi
}

record_finished() {
  local output=
  local notification_id=
  local failure_message="No playable video was produced."
  local -a replace_argument=()

  if [[ -f $plan_file ]] && jq -e '.output_file | type == "string"' "$plan_file" >/dev/null 2>&1; then
    output=$(jq -r '.output_file' "$plan_file")
  fi
  if [[ -f $notification_file ]]; then
    notification_id=$(<"$notification_file")
    if [[ $notification_id =~ ^[0-9]+$ ]]; then
      replace_argument+=("--replace-id=$notification_id")
    fi
    rm -f "$notification_file"
  fi

  if [[ -n $output ]] && [[ -s $output ]] \
    && ffprobe -v error -select_streams v:0 -show_entries stream=codec_type \
      -of default=noprint_wrappers=1:nokey=1 "$output" 2>/dev/null | grep -Fxq video; then
    notify_user "${replace_argument[@]}" --expire-time=8000 --icon=video-x-generic \
      "Recording saved" "$output"
  else
    if [[ -n $output ]]; then
      failure_message="The recording is incomplete or unreadable: $output"
    fi
    notify_user "${replace_argument[@]}" --expire-time=8000 --icon=dialog-error \
      "Recording failed" "$failure_message"
  fi
}

service_active() {
  systemctl --user is-active --quiet "$unit"
}

start_video() {
  local geometry
  local output
  local audio=null
  local temporary

  geometry=$(select_region) || return 0
  geometry=$(normalize_video_geometry "$geometry") || return 1
  if [[ $(audio_status) == on ]]; then
    audio=$(system_audio_device) || return 1
  fi
  output=$(unique_path "$videos_dir" "Screen Recording" mp4)
  temporary=$(mktemp "$runtime_dir/recording.XXXXXX")
  jq -n \
    --arg geometry "$geometry" \
    --arg output "$output" \
    --arg audio "$audio" '
      {
        geometry: $geometry,
        output_file: $output,
        audio_device: (if $audio == "null" then null else $audio end)
      }
    ' > "$temporary"
  chmod 0600 "$temporary"
  mv -f "$temporary" "$plan_file"

  systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP >/dev/null 2>&1 || true
  systemctl --user reset-failed "$unit" >/dev/null 2>&1 || true
  if ! systemctl --user start "$unit"; then
    notify_user "Recording failed" "The recorder service could not start."
    return 1
  fi
  for _ in 1 2 3; do
    if ! service_active; then
      notify_user "Recording failed" "The recorder exited before capture began."
      return 1
    fi
    sleep 0.1
  done

  printf '%s\n' "$output"
}

toggle_video() {
  if service_active; then
    systemctl --user stop "$unit"
  else
    start_video
  fi
}

case "${1:-}" in
  record-service)
    record_service
    exit
    ;;
  record-started)
    record_started
    exit
    ;;
  record-finished)
    record_finished
    exit
    ;;
esac

mkdir -p "$state_dir" "$runtime_dir" "$pictures_dir" "$videos_dir"
chmod 0700 "$state_dir" "$runtime_dir" "$pictures_dir" "$videos_dir"

case "${1:-}" in
  screenshot-full)
    capture_screenshot full
    ;;
  screenshot-region)
    capture_screenshot region
    ;;
  video-toggle)
    exec 9>"$lock_file"
    flock 9
    toggle_video
    ;;
  audio-status)
    audio_status
    ;;
  audio-toggle)
    exec 9>"$lock_file"
    flock 9
    if [[ $(audio_status) == on ]]; then
      set_audio off
    else
      set_audio on
    fi
    ;;
  audio-on)
    exec 9>"$lock_file"
    flock 9
    set_audio on
    ;;
  audio-off)
    exec 9>"$lock_file"
    flock 9
    set_audio off
    ;;
  *)
    printf 'usage: mariano-capture screenshot-full|screenshot-region|video-toggle|audio-status|audio-toggle\n' >&2
    exit 2
    ;;
esac
