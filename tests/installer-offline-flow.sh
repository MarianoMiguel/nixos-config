#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_path="$repo/tests/bin:$PATH"
scratch=$(mktemp -d)

cleanup_test() {
  rm -rf "$scratch"
}
trap cleanup_test EXIT

if rg -q '(^|[[:space:]])disko-install([[:space:]\\]|$)|--option offline true' \
  "$repo/scripts/install-system.sh"; then
  printf 'Installer still uses dynamic disko-install or the unsupported offline setting.\n' >&2
  exit 1
fi

rg -q 'INSTALLER_BALERION_SYSTEM=' "$repo/hosts/installer/configuration.nix"
rg -q 'INSTALLER_BALERION_DISKO_SCRIPT=' "$repo/hosts/installer/configuration.nix"
rg -q 'INSTALLER_BONHART_SYSTEM=' "$repo/hosts/installer/configuration.nix"
rg -q 'INSTALLER_BONHART_DISKO_SCRIPT=' "$repo/hosts/installer/configuration.nix"

mkdir -p \
  "$scratch/state" \
  "$scratch/system" \
  "$scratch/test-mariano-mutable-dotfile-seed/dms" \
  "$scratch/test-mariano-mutable-dotfile-seed/niri/dms" \
  "$scratch/test-mariano-mutable-dotfile-seed/nvim" \
  "$scratch/test-mariano-mutable-dotfile-seed/themeport/neovim"
: > "$scratch/state/install.log"
printf '#!/usr/bin/env bash\n' > "$scratch/system/init"
chmod +x "$scratch/system/init"
cat > "$scratch/disko-script" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$scratch/disko-script"
touch \
  "$scratch/test-mariano-mutable-dotfile-seed/dms/plugin-settings.json" \
  "$scratch/test-mariano-mutable-dotfile-seed/niri/dms/binds.kdl" \
  "$scratch/test-mariano-mutable-dotfile-seed/nvim/lazy-lock.json" \
  "$scratch/test-mariano-mutable-dotfile-seed/themeport/neovim/generated.lua"
printf '%s\n' \
  "$scratch/system" \
  "$scratch/disko-script" \
  "$scratch/test-mariano-mutable-dotfile-seed" \
  > "$scratch/requisites"
printf '%s\n' "$scratch/system" "$scratch/disko-script" > "$scratch/requisites-without-home-seed"
printf '%s\n' 'Retry this step' > "$scratch/choices"

if env \
  PATH="$test_path" \
  INSTALLER_NONINTERACTIVE=0 \
  INSTALLER_STATE_DIR="$scratch/state" \
  INSTALLER_NIX_STORE_REQUISITES="$scratch/requisites-without-home-seed" \
  INSTALLER_BALERION_SYSTEM="$scratch/system" \
  INSTALLER_BALERION_DISKO_SCRIPT="$scratch/disko-script" \
  bash -c '
    set -euo pipefail
    source <(sed '\''/^main "\$@"$/d'\'' "$1/scripts/install-system.sh")
    configuration=balerion
    select_install_payload
    verify_install_payload
  ' _ "$repo"
then
  printf 'Installer accepted a payload without the Home Manager seed.\n' >&2
  exit 1
fi

env \
  PATH="$test_path" \
  INSTALLER_NONINTERACTIVE=0 \
  INSTALLER_STATE_DIR="$scratch/state" \
  INSTALLER_GUM_CHOOSE_QUEUE="$scratch/choices" \
  INSTALLER_NIX_STORE_REQUISITES="$scratch/requisites" \
  INSTALLER_BALERION_SYSTEM="$scratch/system" \
  INSTALLER_BALERION_DISKO_SCRIPT="$scratch/disko-script" \
  INSTALLER_FLOW_TEST_COUNTER="$scratch/attempts" \
  bash -c '
    set -euo pipefail
    source <(sed '\''/^main "\$@"$/d'\'' "$1/scripts/install-system.sh")
    configuration=balerion
    select_install_payload
    verify_install_payload
    flaky_step() {
      local attempts=0
      [[ -f $INSTALLER_FLOW_TEST_COUNTER ]] && read -r attempts < "$INSTALLER_FLOW_TEST_COUNTER"
      attempts=$((attempts + 1))
      printf "%s\n" "$attempts" > "$INSTALLER_FLOW_TEST_COUNTER"
      (( attempts > 1 ))
    }
    run_logged "Recoverable installation step" flaky_step
  ' _ "$repo"

[[ $(< "$scratch/attempts") == 2 ]]
printf 'Installer offline and retry tests passed.\n'
