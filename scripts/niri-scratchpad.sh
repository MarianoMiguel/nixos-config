#!/usr/bin/env bash
set -euo pipefail

state_dir=${NIRI_SCRATCHPAD_STATE_DIR:-${XDG_RUNTIME_DIR:?XDG_RUNTIME_DIR is required}/mariano-niri-scratchpad}
state_file="$state_dir/state.json"
lock_file="$state_dir/lock"

notify_user() {
  if ! notify-send --app-name="Niri Scratchpad" --urgency=low "Scratchpad" "$1" >/dev/null 2>&1; then
    printf 'scratchpad: %s\n' "$1" >&2
  fi
}

niri_json() {
  local payload

  if ! payload=$(niri msg --json "$1"); then
    notify_user "Niri did not answer."
    exit 1
  fi
  if ! jq -e 'type == "array"' >/dev/null <<<"$payload"; then
    notify_user "Niri returned invalid $1 data."
    exit 1
  fi
  printf '%s\n' "$payload"
}

niri_action() {
  niri msg action "$@"
}

load_state() {
  if [[ -f $state_file ]] && jq -e \
    '.version == 1 and ((.outputs | type) == "object")' \
    "$state_file" >/dev/null 2>&1; then
    command cat "$state_file"
  else
    printf '%s\n' '{"version":1,"outputs":{}}'
  fi
}

write_state() {
  local value=$1
  local temporary

  temporary=$(mktemp "$state_file.XXXXXX")
  printf '%s\n' "$value" > "$temporary"
  chmod 0600 "$temporary"
  mv -f "$temporary" "$state_file"
}

focused_workspace() {
  jq -c '[.[] | select(.is_focused == true)] | if length == 1 then .[0] else empty end' \
    <<<"$workspaces"
}

ensure_scratch_workspace() {
  local candidate
  local candidate_idx

  if locate_scratch_workspace; then
    return
  fi

  candidate=$(jq -r \
    --arg output "$output" \
    --argjson current "$current_workspace_id" \
    --argjson windows "$windows" '
      ($windows | map(.workspace_id) | map(select(. != null))) as $occupied
      | [
          .[]
          | . as $workspace
          | select(
              .output == $output
              and .id != $current
              and .name == null
              and (($occupied | index($workspace.id)) == null)
            )
        ]
      | sort_by(.idx)
      | last
      | if . == null then empty else "\(.id) \(.idx)" end
    ' <<<"$workspaces")
  if [[ -z $candidate ]]; then
    notify_user "No empty workspace is available on $output."
    exit 1
  fi

  read -r scratch_workspace_id candidate_idx <<<"$candidate"
  niri_action set-workspace-name "$scratch_name" --workspace "$candidate_idx" >/dev/null
}

locate_scratch_workspace() {
  local existing
  local existing_output

  existing=$(jq -r --arg name "$scratch_name" '
    [.[] | select(.name == $name)]
    | .[0]
    | if . == null then empty else "\(.id)\t\(.output)" end
  ' <<<"$workspaces")
  if [[ -z $existing ]]; then
    return 1
  fi

  IFS=$'\t' read -r scratch_workspace_id existing_output <<<"$existing"
  if [[ $existing_output != "$output" ]]; then
    niri_action move-workspace-to-monitor "$output" --reference "$scratch_name" >/dev/null
  fi
}

mkdir -p "$state_dir"
chmod 0700 "$state_dir"
exec 9>"$lock_file"
flock 9

windows=$(niri_json windows)
workspaces=$(niri_json workspaces)
current_workspace=$(focused_workspace)
if [[ -z $current_workspace ]]; then
  notify_user "No focused display was found."
  exit 1
fi

current_workspace_id=$(jq -r '.id' <<<"$current_workspace")
current_workspace_idx=$(jq -r '.idx' <<<"$current_workspace")
output=$(jq -r '.output // empty' <<<"$current_workspace")
if [[ -z $output ]]; then
  notify_user "The focused workspace has no display."
  exit 1
fi
scratch_name="scratchpad:$output"

state=$(load_state)
state=$(jq --argjson windows "$windows" '
  .outputs |= with_entries(
    .value = (
      (if (.value | type) == "array" then .value else [] end)
      | map(. as $id | select(($windows | map(.id) | index($id)) != null))
    )
  )
' <<<"$state")
write_state "$state"

case "${1:-}" in
  send)
    focused_window_id=$(jq -r '[.[] | select(.is_focused == true)] | .[0].id // empty' <<<"$windows")
    if [[ -z $focused_window_id ]]; then
      notify_user "There is no focused window to move."
      exit 0
    fi

    ensure_scratch_workspace
    niri_action move-window-to-workspace \
      --window-id "$focused_window_id" \
      --focus=false \
      "$scratch_name" >/dev/null

    state=$(jq --arg output "$output" --argjson id "$focused_window_id" '
      .outputs |= with_entries(.value |= map(select(. != $id)))
      | .outputs[$output] = ([$id] + (.outputs[$output] // []))
    ' <<<"$state")
    write_state "$state"
    ;;

  toggle)
    if ! locate_scratch_workspace; then
      notify_user "The scratchpad for $output is empty."
      exit 0
    fi

    window_id=$(jq -r --arg output "$output" '.outputs[$output][0] // empty' <<<"$state")
    if [[ -z $window_id ]]; then
      window_id=$(jq -r --argjson workspace "$scratch_workspace_id" '
        [.
          []
          | select(.workspace_id == $workspace)
        ]
        | sort_by([.focus_timestamp.secs // 0, .focus_timestamp.nanos // 0])
        | reverse
        | .[0].id // empty
      ' <<<"$windows")
      if [[ -n $window_id ]]; then
        state=$(jq --arg output "$output" --argjson id "$window_id" \
          '.outputs[$output] = ([$id] + (.outputs[$output] // []))' <<<"$state")
        write_state "$state"
      fi
    fi
    if [[ -z $window_id ]]; then
      notify_user "The scratchpad for $output is empty."
      exit 0
    fi

    window=$(jq -c --argjson id "$window_id" '.[] | select(.id == $id)' <<<"$windows")
    if [[ $(jq -r '.is_focused' <<<"$window") == true ]]; then
      niri_action move-window-to-workspace \
        --window-id "$window_id" \
        --focus=false \
        "$scratch_name" >/dev/null
      state=$(jq --arg output "$output" --argjson id "$window_id" '
        .outputs[$output] = ((.outputs[$output] | map(select(. != $id))) + [$id])
      ' <<<"$state")
      write_state "$state"
      exit 0
    fi

    if [[ $(jq -r '.workspace_id' <<<"$window") == "$current_workspace_id" ]]; then
      niri_action focus-window --id "$window_id" >/dev/null
      exit 0
    fi

    niri_action move-window-to-workspace --window-id "$window_id" "$current_workspace_idx" >/dev/null
    niri_action move-window-to-floating --id "$window_id" >/dev/null
    niri_action center-window --id "$window_id" >/dev/null
    niri_action focus-window --id "$window_id" >/dev/null
    ;;

  *)
    printf 'usage: niri-scratchpad send|toggle\n' >&2
    exit 2
    ;;
esac
