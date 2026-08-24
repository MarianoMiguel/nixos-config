#!/usr/bin/env bash
set -euo pipefail

umask 077

state_dir=${MARIANO_REMINDER_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/nixos-config/reminders}
lock_file="$state_dir/queue.lock"

now_epoch() {
  if [[ ${MARIANO_REMINDER_DRY_RUN:-0} == 1 && -n ${MARIANO_REMINDER_NOW:-} ]]; then
    printf '%s\n' "$MARIANO_REMINDER_NOW"
  else
    date +%s
  fi
}

ensure_state() {
  mkdir -p "$state_dir"
  chmod 0700 "$state_dir"
}

notify_user() {
  if [[ ${MARIANO_REMINDER_DRY_RUN:-0} == 1 ]]; then
    printf 'notification: %s | %s\n' "$1" "$2"
  else
    notify-send --app-name=Reminders --urgency=normal -- "$1" "$2"
  fi
}

valid_reminder() {
  jq -e '
    type == "object"
    and (.version == 1)
    and (.due | type == "number" and floor == . and . > 0)
    and (.created | type == "number" and floor == . and . > 0)
    and (.message | type == "string" and length > 0 and length <= 500)
  ' "$1" >/dev/null 2>&1
}

add_reminder() {
  local minutes=${1:-}
  local message
  local created
  local due
  local temporary
  local target

  if [[ ! $minutes =~ ^[0-9]+$ ]] || ((minutes == 0 || minutes > 525600)); then
    printf 'Minutes must be a whole number between 1 and 525600.\n' >&2
    exit 2
  fi
  shift
  message=$*
  if [[ -z $message ]]; then
    message="Your ${minutes}-minute reminder is due."
  fi
  ((${#message} <= 500)) || {
    printf 'Reminder text must be 500 characters or fewer.\n' >&2
    exit 2
  }

  ensure_state
  created=$(now_epoch)
  due=$((created + minutes * 60))
  temporary=$(mktemp "$state_dir/.reminder.XXXXXX")
  jq -n \
    --argjson created "$created" \
    --argjson due "$due" \
    --arg message "$message" \
    '{version: 1, created: $created, due: $due, message: $message}' > "$temporary"
  chmod 0600 "$temporary"
  target="$state_dir/$created-${temporary##*.}.json"
  mv -f -- "$temporary" "$target"

  notify_user "Reminder set" "$message · $(date -d "@$due" '+%H:%M')"
}

list_json() {
  local path
  local payload='[]'

  ensure_state
  shopt -s nullglob
  for path in "$state_dir"/*.json; do
    valid_reminder "$path" || continue
    payload=$(jq -cn --argjson current "$payload" --slurpfile item "$path" \
      '$current + [$item[0]]')
  done
  jq -c 'sort_by(.due)' <<< "$payload"
}

show_reminders() {
  local payload
  local count
  local now

  payload=$(list_json)
  count=$(jq 'length' <<< "$payload")
  if ((count == 0)); then
    printf 'No reminders are scheduled.\n'
    return
  fi

  now=$(now_epoch)
  jq -r --argjson now "$now" '
    .[]
    | ((.due - $now) / 60 | ceil) as $minutes
    | "\(.message)\n  in \($minutes)m"
  ' <<< "$payload"
}

deliver_due() {
  local now
  local path
  local due
  local message

  ensure_state
  exec 9> "$lock_file"
  flock -n 9 || exit 0
  now=$(now_epoch)
  shopt -s nullglob
  for path in "$state_dir"/*.json; do
    valid_reminder "$path" || continue
    due=$(jq -r '.due' "$path")
    ((due <= now)) || continue
    message=$(jq -r '.message' "$path")
    if notify_user "Reminder" "$message"; then
      rm -f -- "$path"
    fi
  done
}

clear_reminders() {
  local path

  ensure_state
  exec 9> "$lock_file"
  flock 9
  shopt -s nullglob
  for path in "$state_dir"/*.json; do
    rm -f -- "$path"
  done
  notify_user "Reminders cleared" "All scheduled reminders were removed."
}

interactive_add() {
  local choice
  local minutes
  local message

  choice=$(gum choose --header "When should I remind you?" \
    "5 minutes" "15 minutes" "30 minutes" "1 hour" "2 hours" "Custom") || return 0
  case "$choice" in
    "5 minutes") minutes=5 ;;
    "15 minutes") minutes=15 ;;
    "30 minutes") minutes=30 ;;
    "1 hour") minutes=60 ;;
    "2 hours") minutes=120 ;;
    Custom)
      minutes=$(gum input --prompt "Minutes: " --placeholder "45") || return 0
      ;;
  esac
  message=$(gum input --prompt "Reminder: " --placeholder "What should I remember?") || return 0
  add_reminder "$minutes" "$message"
}

interactive() {
  local choice

  while choice=$(gum choose --header "Reminders" \
    "Set reminder" "Show reminders" "Clear all reminders" "Close"); do
    case "$choice" in
      "Set reminder") interactive_add ;;
      "Show reminders")
        show_reminders
        gum input --prompt "Press Enter to continue " >/dev/null || true
        ;;
      "Clear all reminders")
        if gum confirm "Clear every scheduled reminder?"; then
          clear_reminders
        fi
        ;;
      Close) return 0 ;;
    esac
  done
}

case ${1:-} in
  add)
    shift
    add_reminder "$@"
    ;;
  list|show)
    show_reminders
    ;;
  json)
    list_json
    ;;
  deliver)
    deliver_due
    ;;
  clear)
    clear_reminders
    ;;
  interactive|-i|--interactive)
    interactive
    ;;
  *)
    printf 'usage: mariano-reminder add MINUTES [MESSAGE] | list | json | clear | interactive\n' >&2
    exit 2
    ;;
esac
