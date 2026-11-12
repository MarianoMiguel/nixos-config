set -eu

# Use the clicked display, even when keyboard focus is on another monitor.
# Named empty workspaces may exist before Niri's trailing empty workspace, so
# choose by distance from this output's active workspace rather than list order.
target=$(
  niri msg -j workspaces | jq -r --arg output "${1:-}" '
    . as $all
    | (if $output != "" then $output else (map(select(.is_focused))[0].output) end) as $out
    | ($all | map(select(.output == $out and .is_active))[0]) as $current
    | if $current == null or $current.active_window_id == null then empty
      else
        $all | map(select(.output == $out and .active_window_id == null))
        | sort_by([((.idx - $current.idx) | fabs), .idx])
        | if length == 0 then empty else .[0] | [.output, .idx] | @tsv end
      end
  '
)

if [ -n "${target:-}" ]; then
  IFS=$'\t' read -r output idx <<< "$target"
  niri msg action focus-monitor "$output" >/dev/null
  exec niri msg action focus-workspace "$idx"
fi
