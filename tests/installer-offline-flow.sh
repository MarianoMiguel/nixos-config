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

# Setuid binaries only work through the wrapper directory on NixOS. A nix
# store sudo path in the autostart entry aborts with "must be owned by uid 0
# and have the setuid bit set" on every boot of the ISO.
if rg -q '\$\{pkgs\.sudo\}' "$repo/hosts/installer/configuration.nix"; then
  printf 'Installer desktop entry must use /run/wrappers/bin/sudo, not store sudo.\n' >&2
  exit 1
fi
rg -q '/run/wrappers/bin/sudo' "$repo/hosts/installer/configuration.nix"

# The installer wrapper pins the offline system and disko store paths for
# every host the image embeds, and tells the wizard which hosts those are.
rg -q 'INSTALLER_AVAILABLE_HOSTS=' "$repo/hosts/installer/configuration.nix"
rg -q 'INSTALLER_\$\{upper\}_SYSTEM=' "$repo/hosts/installer/configuration.nix"
rg -q 'INSTALLER_\$\{upper\}_DISKO_SCRIPT=' "$repo/hosts/installer/configuration.nix"
rg -q 'INSTALLER_BALERION_SYSTEM' "$repo/scripts/install-system.sh"
rg -q 'INSTALLER_BONHART_SYSTEM' "$repo/scripts/install-system.sh"

# A single-host image selects its only configuration without asking, and a
# noninteractive request for a host the image does not contain must fail.
env \
  PATH="$test_path" \
  INSTALLER_NONINTERACTIVE=0 \
  INSTALLER_STATE_DIR="$scratch/state" \
  INSTALLER_AVAILABLE_HOSTS=bonhart \
  bash -c '
    set -euo pipefail
    source <(sed '\''/^main "\$@"$/d'\'' "$1/scripts/install-system.sh")
    choose_configuration >/dev/null
    printf "%s\n" "$configuration" > "$2"
  ' _ "$repo" "$scratch/single-host"
[[ $(< "$scratch/single-host") == bonhart ]]

if env \
  PATH="$test_path" \
  INSTALLER_NONINTERACTIVE=1 \
  INSTALLER_STATE_DIR="$scratch/state" \
  INSTALLER_AVAILABLE_HOSTS=balerion \
  INSTALLER_CONFIGURATION=bonhart \
  bash -c '
    set -euo pipefail
    source <(sed '\''/^main "\$@"$/d'\'' "$1/scripts/install-system.sh")
    choose_configuration >/dev/null 2>&1
  ' _ "$repo"
then
  printf 'Installer accepted a configuration its image does not contain.\n' >&2
  exit 1
fi

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
# Mutable dotfiles are out-of-store symlinks into the installed user's home
# state; in the live installer session they dangle by design and must still
# count as present payload.
ln -s /nonexistent/mutable-state-target "$scratch/dangling-mutable-dotfile"
printf '%s\n' \
  "$scratch/system" \
  "$scratch/disko-script" \
  "$scratch/dangling-mutable-dotfile" \
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
