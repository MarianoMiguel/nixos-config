#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
scratch=$(mktemp -d)
fake_bin="$scratch/bin"
action_log="$scratch/actions.log"
windows_fixture="$scratch/windows.json"
workspaces_fixture="$scratch/workspaces.json"
daemon_pid=""

cleanup() {
  if [[ -n $daemon_pid ]]; then
    kill "$daemon_pid" 2>/dev/null || true
  fi
  rm -rf "$scratch"
}
trap cleanup EXIT

mkdir -p "$fake_bin"
: > "$action_log"

cat > "$fake_bin/niri" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "$1 $2 ${3:-}" in
  "msg --json windows")
    command cat "$TEST_WINDOWS_FIXTURE"
    ;;
  "msg --json workspaces")
    command cat "$TEST_WORKSPACES_FIXTURE"
    ;;
  "msg --json event-stream")
    exec tail -f /dev/null
    ;;
  "msg action "*)
    shift 2
    printf '%s' "$1" >> "$TEST_ACTION_LOG"
    shift
    if (( $# > 0 )); then
      printf ' %s' "$@" >> "$TEST_ACTION_LOG"
    fi
    printf '\n' >> "$TEST_ACTION_LOG"
    ;;
  *)
    printf 'unexpected niri invocation: %s\n' "$*" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$fake_bin/niri"

cat > "$workspaces_fixture" <<'EOF'
[
  {"id": 1, "idx": 1, "name": null, "output": "eDP-1", "is_active": true, "is_focused": true},
  {"id": 2, "idx": 1, "name": null, "output": "DP-3", "is_active": true, "is_focused": false},
  {"id": 3, "idx": 2, "name": null, "output": "eDP-1", "is_active": false, "is_focused": false}
]
EOF

cat > "$windows_fixture" <<'EOF'
[
  {"id": 10, "app_id": "Alacritty", "title": "terminal", "workspace_id": 1, "is_focused": true, "is_floating": false, "layout": {"pos_in_scrolling_layout": [0, 0]}},
  {"id": 11, "app_id": "zen", "title": "browser", "workspace_id": 1, "is_focused": false, "is_floating": false, "layout": {"pos_in_scrolling_layout": [1, 0]}},
  {"id": 12, "app_id": "org.gnome.Nautilus", "title": "files", "workspace_id": 1, "is_focused": false, "is_floating": true, "layout": {"pos_in_scrolling_layout": [0, 0]}},
  {"id": 13, "app_id": "Alacritty", "title": "remote", "workspace_id": 2, "is_focused": false, "is_floating": false, "layout": {"pos_in_scrolling_layout": [0, 0]}},
  {"id": 14, "app_id": "com.danklinux.dms", "title": "shell", "workspace_id": 1, "is_focused": false, "is_floating": true}
]
EOF

modes() {
  env \
    PATH="$fake_bin:$PATH" \
    XDG_RUNTIME_DIR="$scratch" \
    TEST_ACTION_LOG="$action_log" \
    TEST_WINDOWS_FIXTURE="$windows_fixture" \
    TEST_WORKSPACES_FIXTURE="$workspaces_fixture" \
    python3 "$repo/scripts/niri-modes.py" "$@"
}

fail() {
  echo "FAIL: $1" >&2
  echo "--- action log ---" >&2
  command cat "$action_log" >&2 || true
  exit 1
}

actions_since() {
  sed -n "$(( $1 + 1 )),\$p" "$action_log"
}

modes daemon &
daemon_pid=$!

for _ in $(seq 1 50); do
  if [[ -S "$scratch/niri-modes.sock" ]] && modes get 2>/dev/null | grep -q '"eDP-1"'; then
    break
  fi
  sleep 0.1
done
modes get | grep -q '"eDP-1"' || fail "daemon did not come up with workspace state"

# Everything starts as passive tile: no actions at all so far.
[[ ! -s $action_log ]] || fail "daemon acted without being asked"
modes get | grep -q '"mode": "tile"' || fail "initial mode is not tile"

# Float mode floats only this workspace's tiled, non-exempt windows.
mark=$(wc -l < "$action_log")
modes set float --output eDP-1
step=$(actions_since "$mark")
grep -q 'move-window-to-floating --id 10' <<<"$step" || fail "did not float window 10"
grep -q 'move-window-to-floating --id 11' <<<"$step" || fail "did not float window 11"
grep -q 'id 12' <<<"$step" && fail "touched the already-floating window 12"
grep -q 'id 13' <<<"$step" && fail "leaked onto the other monitor's workspace"
grep -q 'id 14' <<<"$step" && fail "touched the exempt shell window"
modes get | grep -q '"1": "float"' || fail "workspace 1 mode is not float"

# Focus mode consolidates into one centered tabbed column at the focus width.
mark=$(wc -l < "$action_log")
modes set focus --output eDP-1
step=$(actions_since "$mark")
grep -q 'move-window-to-tiling --id 12' <<<"$step" || fail "did not re-tile the floating window"
grep -q 'focus-window --id 10' <<<"$step" || fail "did not focus the base window"
grep -q 'consume-window-into-column' <<<"$step" || fail "did not merge columns"
grep -q 'set-column-display tabbed' <<<"$step" || fail "did not set tabbed display"
grep -q 'set-column-width 80%' <<<"$step" || fail "did not apply the focus width"
grep -q 'center-window --id 10' <<<"$step" || fail "did not center the column"
grep -q 'id 13' <<<"$step" && fail "focus mode leaked onto the other monitor"

# Cycling the other monitor's mode must not disturb workspace 1.
mark=$(wc -l < "$action_log")
modes cycle-mode --output DP-3
step=$(actions_since "$mark")
grep -q 'move-window-to-floating --id 13' <<<"$step" || fail "cycle-mode did not float the other monitor"
state=$(modes get)
grep -q '"2": "float"' <<<"$state" || fail "workspace 2 mode is not float"
grep -q '"1": "focus"' <<<"$state" || fail "workspace 1 lost its focus mode"

# One scroll step = one app while the focused workspace is in focus mode.
mark=$(wc -l < "$action_log")
modes cycle next
actions_since "$mark" | grep -q 'focus-window-down' || fail "cycle next did not step within the column"

# Returning to tile splits the focus column back into columns.
mark=$(wc -l < "$action_log")
modes set tile --output eDP-1
step=$(actions_since "$mark")
grep -q 'move-window-to-tiling --id 12' <<<"$step" || fail "tile did not re-tile floating windows"
grep -q 'set-column-display normal' <<<"$step" || fail "tile did not restore normal column display"
grep -q 'expel-window-from-column' <<<"$step" || fail "tile did not split the column"
modes get | grep -q '"1":' && fail "workspace 1 still carries an explicit mode"

echo "PASS niri-modes"
