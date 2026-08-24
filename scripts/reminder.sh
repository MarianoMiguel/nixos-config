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

  if [[ ! $minutes =~ ^[0-9]+$ ]] || ((minutes == 0 || minutes > 5256000)); then
    printf 'Minutes must be a whole number between 1 and 5256000.\n' >&2
    exit 2
  fi
  shift
  message=$*
  if [[ -z $message ]]; then
    message="Your ${minutes}-minute reminder is due."
  fi

  created=$(now_epoch)
  due=$((created + minutes * 60))
  save_reminder "$created" "$due" "$message"
}

save_reminder() {
  local created=$1
  local due=$2
  local message=$3
  local temporary
  local target

  if [[ ! $created =~ ^[0-9]+$ || ! $due =~ ^[0-9]+$ ]] || ((due <= created)); then
    printf 'The reminder must be scheduled for a future time.\n' >&2
    exit 2
  fi
  ((${#message} <= 500)) || {
    printf 'Reminder text must be 500 characters or fewer.\n' >&2
    exit 2
  }

  ensure_state
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

add_relative_reminder() {
  local amount=${1:-}
  local unit=${2:-}
  local message
  local created
  local due
  local maximum
  local seconds_per_unit
  local base

  case "$unit" in
    minute|minutes) unit=minutes; maximum=5256000; seconds_per_unit=60 ;;
    hour|hours) unit=hours; maximum=87600; seconds_per_unit=3600 ;;
    day|days) unit=days; maximum=3650; seconds_per_unit=86400 ;;
    week|weeks) unit=weeks; maximum=520; seconds_per_unit=604800 ;;
    month|months) unit=months; maximum=120; seconds_per_unit=0 ;;
    *)
      printf 'Unit must be minutes, hours, days, weeks, or months.\n' >&2
      exit 2
      ;;
  esac
  if [[ ! $amount =~ ^[0-9]+$ ]] || ((amount == 0 || amount > maximum)); then
    printf 'Amount must be a whole number between 1 and %s %s.\n' "$maximum" "$unit" >&2
    exit 2
  fi
  shift 2
  message=$*
  if [[ -z $message ]]; then
    message="Your reminder for ${amount} ${unit} is due."
  fi

  created=$(now_epoch)
  if [[ $unit == months ]]; then
    # Calendar months intentionally preserve the local day and time. Using a
    # fixed number of days here would make longer reminders drift noticeably.
    base=$(date -d "@$created" --iso-8601=seconds)
    due=$(date -d "$base +$amount months" +%s) || {
      printf 'Could not calculate that calendar date.\n' >&2
      exit 2
    }
  else
    due=$((created + amount * seconds_per_unit))
  fi
  save_reminder "$created" "$due" "$message"
}

add_absolute_reminder() {
  local date_value=${1:-}
  local time_value=${2:-}
  local message
  local created
  local due
  local normalized

  if [[ ! $date_value =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ \
    || ! $time_value =~ ^[0-9]{2}:[0-9]{2}$ ]]; then
    printf 'Date and time must use YYYY-MM-DD and HH:MM.\n' >&2
    exit 2
  fi
  shift 2
  message=$*
  if [[ -z $message ]]; then
    message="Your scheduled reminder is due."
  fi

  due=$(date -d "$date_value $time_value" +%s 2>/dev/null) || {
    printf 'That date or time is not valid.\n' >&2
    exit 2
  }
  normalized=$(date -d "@$due" '+%F %H:%M')
  if [[ $normalized != "$date_value $time_value" ]]; then
    printf 'That date or time is not valid in the local timezone.\n' >&2
    exit 2
  fi
  created=$(now_epoch)
  save_reminder "$created" "$due" "$message"
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
  local amount
  local unit
  local date_value
  local time_value
  local minutes
  local message

  choice=$(gum choose --header "When should I remind you?" \
    "5 minutes" "15 minutes" "1 hour" "24 hours" "1 week" \
    "Custom duration" "Specific date and time") || return 0
  case "$choice" in
    "5 minutes") minutes=5 ;;
    "15 minutes") minutes=15 ;;
    "1 hour") minutes=60 ;;
    "24 hours") minutes=1440 ;;
    "1 week") minutes=10080 ;;
    "Custom duration")
      amount=$(gum input --prompt "Amount: " --placeholder "48") || return 0
      unit=$(gum choose --header "Unit" minutes hours days weeks months) || return 0
      message=$(gum input --prompt "Reminder: " --placeholder "What should I remember?") || return 0
      add_relative_reminder "$amount" "$unit" "$message"
      return
      ;;
    "Specific date and time")
      date_value=$(gum input --prompt "Date: " --placeholder "$(date '+%F')") || return 0
      time_value=$(gum input --prompt "Time: " --placeholder "18:30") || return 0
      message=$(gum input --prompt "Reminder: " --placeholder "What should I remember?") || return 0
      add_absolute_reminder "$date_value" "$time_value" "$message"
      return
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
  in)
    shift
    add_relative_reminder "$@"
    ;;
  at)
    shift
    add_absolute_reminder "$@"
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
    printf 'usage: mariano-reminder add MINUTES [MESSAGE] | in AMOUNT UNIT [MESSAGE] | at YYYY-MM-DD HH:MM [MESSAGE] | list | json | clear | interactive\n' >&2
    exit 2
    ;;
esac
