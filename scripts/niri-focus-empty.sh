set -eu

# Focus the always-empty trailing workspace on the focused output.
#
# Niri keeps exactly one empty workspace at the end of each output. active_window_id
# is null only for an empty workspace, so it uniquely identifies that trailing one;
# focus-workspace takes the per-output index (idx). Do nothing if none is found.
idx=$(
  niri msg -j workspaces | jq -r '
    (map(select(.is_focused))[0].output) as $out
    | map(select(.output == $out and .active_window_id == null))
    | (first(.[].idx) // empty)
  '
)

if [ -n "${idx:-}" ]; then
  exec niri msg action focus-workspace "$idx"
fi
