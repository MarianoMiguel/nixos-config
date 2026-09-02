#!/usr/bin/env bash
# Themeport's kdeglobals renderer: Qt and KDE applications must receive a
# palette whose roles follow the theme's mode. Dark themes raise the window
# chrome above the page (lighter), light themes lower it (darker), and the
# selection text must always contrast with the selection colour.
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

render() {
  python3 "$repo/tools/themeport/themeport.py" render \
    "$repo/tests/fixtures/themeport/$1" --output "$scratch/$1" >/dev/null
  test -f "$scratch/$1/kdeglobals"
}

key() {
  # key FILE SECTION KEY -> value
  awk -v section="[$2]" -v key="$3" '
    $0 == section { inside = 1; next }
    /^\[/ { inside = 0 }
    inside && index($0, key "=") == 1 { print substr($0, length(key) + 2); exit }
  ' "$1"
}

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

render dark
render light
dark="$scratch/dark/kdeglobals"
light="$scratch/light/kdeglobals"

[[ $(key "$dark" 'Colors:View' BackgroundNormal) == "26,27,38" ]] || fail "dark page is not the theme background"
[[ $(key "$dark" 'Colors:Window' BackgroundNormal) == "36,40,59" ]] || fail "dark window chrome should be the lighter background"
[[ $(key "$light" 'Colors:View' BackgroundNormal) == "255,252,240" ]] || fail "light page is not the theme background"
[[ $(key "$light" 'Colors:Window' BackgroundNormal) == "242,240,229" ]] || fail "light window chrome should be the dark background"

for file in "$dark" "$light"; do
  [[ $(key "$file" 'Colors:Selection' BackgroundNormal) != $(key "$file" 'Colors:Selection' ForegroundNormal) ]] \
    || fail "selection text does not contrast in $file"
  [[ $(key "$file" General ColorScheme) == "Themeport" ]] || fail "scheme name missing in $file"
  [[ $(key "$file" General font) == Inter,* ]] || fail "UI font is not Inter in $file"
  [[ $(key "$file" General fixed) == "JetBrainsMonoNL NFM",* ]] || fail "monospace font is wrong in $file"
  [[ -n $(key "$file" Icons Theme) ]] || fail "icon theme missing in $file"
  [[ $(key "$file" KDE widgetStyle) == "Breeze" ]] || fail "widget style is not Breeze in $file"
done

# Fixtures carry no icons.theme, so the renderer must fall back per mode.
[[ $(key "$dark" Icons Theme) == "breeze-dark" ]] || fail "dark icon fallback"
[[ $(key "$light" Icons Theme) == "breeze" ]] || fail "light icon fallback"

printf 'Themeport kdeglobals rendering passed.\n'
