#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
scratch=$(mktemp -d)

cleanup_test() {
  rm -rf "$scratch"
}
trap cleanup_test EXIT

printf '%s' 'disk:unlock password' > "$scratch/input"
mkdir -p "$scratch/state"

INSTALLER_NONINTERACTIVE=1 \
INSTALLER_STATE_DIR="$scratch/state" \
bash -c '
  set -euo pipefail
  source <(sed '\''/^main "\$@"$/d'\'' "$1/scripts/install-system.sh")
  before=$(umask)
  prompt_password_pair \
    "LUKS password" \
    "Test password" \
    "$INSTALLER_STATE_DIR/output" \
    "$INSTALLER_STATE_DIR/../input"
  after=$(umask)
  [[ $after == "$before" ]] || {
    printf "Password collection leaked umask: before=%s after=%s\n" "$before" "$after" >&2
    exit 1
  }
  [[ $(stat -c "%a" "$INSTALLER_STATE_DIR/output" 2>/dev/null || stat -f "%Lp" "$INSTALLER_STATE_DIR/output") == 600 ]]
' _ "$repo"

printf 'Installer secret-permission tests passed.\n'
