#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
scratch=$(mktemp -d)
fake_bin="$scratch/bin"
state_dir="$scratch/state"
action_log="$scratch/actions.log"
windows_fixture="$scratch/windows.json"
workspaces_fixture="$scratch/workspaces.json"

cleanup() {
  rm -rf "$scratch"
}
trap cleanup EXIT

mkdir -p "$fake_bin"

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
  "msg action "*)
    shift 2
    printf '%s' "$1" >> "$TEST_ACTION_LOG"
    shift
    printf ' %s' "$@" >> "$TEST_ACTION_LOG"
    printf '\n' >> "$TEST_ACTION_LOG"
    ;;
  *)
    printf 'unexpected niri invocation: %s\n' "$*" >&2
    exit 1
    ;;
esac
EOF

cat > "$fake_bin/flock" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat > "$fake_bin/notify-send" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

chmod +x "$fake_bin/niri" "$fake_bin/flock" "$fake_bin/notify-send"

run_scratchpad() {
  env \
    PATH="$fake_bin:$PATH" \
    NIRI_SCRATCHPAD_STATE_DIR="$state_dir" \
    TEST_ACTION_LOG="$action_log" \
    TEST_WINDOWS_FIXTURE="$windows_fixture" \
    TEST_WORKSPACES_FIXTURE="$workspaces_fixture" \
    "$repo/scripts/niri-scratchpad.sh" "$1"
}

assert_action() {
  grep -Fxq "$1" "$action_log"
}

assert_no_action() {
  if grep -Fq -- "$1" "$action_log"; then
    printf 'unexpected action containing %s:\n' "$1" >&2
    cat "$action_log" >&2
    exit 1
  fi
}

cat > "$windows_fixture" <<'EOF'
[
  {"id":10,"workspace_id":1,"is_focused":true,"is_floating":false,"focus_timestamp":{"secs":20,"nanos":0}},
  {"id":20,"workspace_id":3,"is_focused":false,"is_floating":false,"focus_timestamp":{"secs":10,"nanos":0}}
]
EOF
cat > "$workspaces_fixture" <<'EOF'
[
  {"id":1,"idx":1,"name":null,"output":"eDP-1","is_focused":true},
  {"id":2,"idx":2,"name":null,"output":"eDP-1","is_focused":false},
  {"id":5,"idx":3,"name":"Chat","output":"eDP-1","is_focused":false},
  {"id":3,"idx":1,"name":null,"output":"HDMI-A-1","is_focused":false},
  {"id":4,"idx":2,"name":null,"output":"HDMI-A-1","is_focused":false}
]
EOF

run_scratchpad send
assert_action 'set-workspace-name scratchpad:eDP-1 --workspace 2'
assert_action 'move-window-to-workspace --window-id 10 --focus=false scratchpad:eDP-1'
jq -e '.outputs["eDP-1"] == [10]' "$state_dir/state.json" >/dev/null

: > "$action_log"
cat > "$windows_fixture" <<'EOF'
[
  {"id":10,"workspace_id":2,"is_focused":false,"is_floating":false,"focus_timestamp":{"secs":20,"nanos":0}},
  {"id":11,"workspace_id":1,"is_focused":true,"is_floating":false,"focus_timestamp":{"secs":21,"nanos":0}}
]
EOF
cat > "$workspaces_fixture" <<'EOF'
[
  {"id":1,"idx":1,"name":null,"output":"eDP-1","is_focused":true},
  {"id":2,"idx":2,"name":"scratchpad:eDP-1","output":"eDP-1","is_focused":false}
]
EOF

run_scratchpad toggle
assert_action 'move-window-to-workspace --window-id 10 1'
assert_action 'move-window-to-floating --id 10'
assert_action 'center-window --id 10'
assert_action 'focus-window --id 10'

: > "$action_log"
cat > "$windows_fixture" <<'EOF'
[
  {"id":10,"workspace_id":1,"is_focused":true,"is_floating":true,"focus_timestamp":{"secs":22,"nanos":0}}
]
EOF
run_scratchpad toggle
assert_action 'move-window-to-workspace --window-id 10 --focus=false scratchpad:eDP-1'

: > "$action_log"
cat > "$state_dir/state.json" <<'EOF'
{"version":1,"outputs":{"eDP-1":[10],"HDMI-A-1":[20]}}
EOF
cat > "$windows_fixture" <<'EOF'
[
  {"id":10,"workspace_id":2,"is_focused":false,"is_floating":true,"focus_timestamp":{"secs":20,"nanos":0}},
  {"id":20,"workspace_id":4,"is_focused":false,"is_floating":false,"focus_timestamp":{"secs":30,"nanos":0}},
  {"id":21,"workspace_id":3,"is_focused":true,"is_floating":false,"focus_timestamp":{"secs":31,"nanos":0}}
]
EOF
cat > "$workspaces_fixture" <<'EOF'
[
  {"id":1,"idx":1,"name":null,"output":"eDP-1","is_focused":false},
  {"id":2,"idx":2,"name":"scratchpad:eDP-1","output":"eDP-1","is_focused":false},
  {"id":3,"idx":1,"name":null,"output":"HDMI-A-1","is_focused":true},
  {"id":4,"idx":2,"name":"scratchpad:HDMI-A-1","output":"HDMI-A-1","is_focused":false}
]
EOF

run_scratchpad toggle
assert_action 'move-window-to-workspace --window-id 20 1'
assert_no_action '--window-id 10'

: > "$action_log"
cat > "$state_dir/state.json" <<'EOF'
{"version":1,"outputs":{"eDP-1":[10,12]}}
EOF
cat > "$windows_fixture" <<'EOF'
[
  {"id":10,"workspace_id":1,"is_focused":true,"is_floating":true,"focus_timestamp":{"secs":40,"nanos":0}},
  {"id":12,"workspace_id":2,"is_focused":false,"is_floating":true,"focus_timestamp":{"secs":39,"nanos":0}}
]
EOF
cat > "$workspaces_fixture" <<'EOF'
[
  {"id":1,"idx":1,"name":null,"output":"eDP-1","is_focused":true},
  {"id":2,"idx":2,"name":"scratchpad:eDP-1","output":"eDP-1","is_focused":false}
]
EOF

run_scratchpad toggle
jq -e '.outputs["eDP-1"] == [12,10]' "$state_dir/state.json" >/dev/null

: > "$action_log"
cat > "$windows_fixture" <<'EOF'
[
  {"id":10,"workspace_id":2,"is_focused":false,"is_floating":true,"focus_timestamp":{"secs":40,"nanos":0}},
  {"id":12,"workspace_id":2,"is_focused":false,"is_floating":true,"focus_timestamp":{"secs":39,"nanos":0}},
  {"id":11,"workspace_id":1,"is_focused":true,"is_floating":false,"focus_timestamp":{"secs":41,"nanos":0}}
]
EOF
run_scratchpad toggle
assert_action 'move-window-to-workspace --window-id 12 1'
assert_no_action '--window-id 10 1'

: > "$action_log"
cat > "$state_dir/state.json" <<'EOF'
{"version":1,"outputs":{"eDP-1":[10]}}
EOF
cat > "$windows_fixture" <<'EOF'
[
  {"id":10,"workspace_id":2,"is_focused":false,"is_floating":true,"focus_timestamp":{"secs":50,"nanos":0}},
  {"id":11,"workspace_id":1,"is_focused":true,"is_floating":false,"focus_timestamp":{"secs":51,"nanos":0}}
]
EOF
cat > "$workspaces_fixture" <<'EOF'
[
  {"id":1,"idx":1,"name":null,"output":"eDP-1","is_focused":true},
  {"id":2,"idx":3,"name":"scratchpad:eDP-1","output":"HDMI-A-1","is_focused":false}
]
EOF

run_scratchpad toggle
assert_action 'move-workspace-to-monitor eDP-1 --reference scratchpad:eDP-1'
assert_action 'move-window-to-workspace --window-id 10 1'

printf 'Niri scratchpad behavior passed.\n'
