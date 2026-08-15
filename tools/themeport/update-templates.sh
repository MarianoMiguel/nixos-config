#!/usr/bin/env bash
# Re-vendor Omarchy's themed templates from upstream (quattro branch).
# themeport renders through these, so pulling them forward is how we inherit
# upstream theming improvements. Review the diff, run tests.py, then rebuild.
set -euo pipefail

cd "$(dirname "$0")/templates/omarchy"

files=(
  alacritty.toml btop.theme chromium.theme claude.json foot.ini ghostty.conf
  gum_env.lua helix.toml hyprland.lua keyboard.rgb kitty.conf neovim.lua
  obsidian.css pi.json shell.toml vscode-theme.json
)

for f in "${files[@]}"; do
  curl -sf "https://raw.githubusercontent.com/basecamp/omarchy/quattro/default/themed/$f.tpl" -o "$f.tpl"
  echo "updated $f.tpl"
done

rev=$(curl -sf "https://api.github.com/repos/basecamp/omarchy/commits/quattro" | python3 -c 'import json,sys; print(json.load(sys.stdin)["sha"])')
echo "$rev" > UPSTREAM_REV
echo "pinned upstream rev: $rev"
echo "now run: python3 ../../tests.py"
