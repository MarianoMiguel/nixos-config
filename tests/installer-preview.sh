#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fixture="$repo/tests/fixtures/lsblk-disks.json"
test_path="$repo/tests/bin:$PATH"
scratch=$(mktemp -d)

cleanup() {
  rm -rf "$scratch"
}
trap cleanup EXIT

printf '%s' 'disk:unlock password' > "$scratch/luks.input"
printf '%s' 'desktop:login password' > "$scratch/user.input"
printf '%s' 'sudo:administrator password' > "$scratch/sudo.input"

run_preview() {
  local configuration=$1
  local disk=$2
  local confirmation=$3
  local state=$4

  env \
    PATH="$test_path" \
    TERM=xterm-256color \
    INSTALLER_NONINTERACTIVE=1 \
    INSTALLER_CONFIGURATION="$configuration" \
    INSTALLER_DISK="$disk" \
    INSTALLER_EXCLUDED_DISK=/dev/sda \
    INSTALLER_CONFIRMATION="$confirmation" \
    INSTALLER_LSBLK_JSON="$fixture" \
    INSTALLER_LUKS_PASSWORD_FILE="$scratch/luks.input" \
    INSTALLER_USER_PASSWORD_FILE="$scratch/user.input" \
    INSTALLER_SUDO_PASSWORD_FILE="$scratch/sudo.input" \
    INSTALLER_STATE_DIR="$state" \
    "$repo/scripts/install-system.sh" --preview
}

assert_no_secrets() {
  local state=$1

  [[ ! -e $state/luks-password ]]
  [[ ! -e $state/user-password ]]
  [[ ! -e $state/sudo-password ]]
}

interactive_state="$scratch/interactive-state"
interactive_choices="$scratch/interactive-choices"
interactive_inputs="$scratch/interactive-inputs"
cat > "$interactive_choices" <<'EOF'
Balerion  · Intel 13900KF + RTX 3080 Ti
/dev/nvme0n1  ·  1.8 TiB  ·  Test NVMe  ·  nvme
EOF
cat > "$interactive_inputs" <<'EOF'
disk:unlock password
disk:unlock password
desktop:login password
desktop:login password
sudo:administrator password
sudo:administrator password
ERASE /nvme0n1
ERASE /dev/nvme0n1
EOF
interactive_output=$(env \
  PATH="$test_path" \
  TERM=xterm-256color \
  INSTALLER_NONINTERACTIVE=0 \
  INSTALLER_EXCLUDED_DISK=/dev/sda \
  INSTALLER_LSBLK_JSON="$fixture" \
  INSTALLER_GUM_CHOOSE_QUEUE="$interactive_choices" \
  INSTALLER_GUM_INPUT_QUEUE="$interactive_inputs" \
  INSTALLER_STATE_DIR="$interactive_state" \
  "$repo/scripts/install-system.sh" --preview)
grep -q 'The erase confirmation did not match. Try again.' <<<"$interactive_output"
grep -q 'Preview complete. No disks were changed.' <<<"$interactive_output"
assert_no_secrets "$interactive_state"

balerion_state="$scratch/balerion-state"
balerion_output=$(run_preview balerion /dev/nvme0n1 'ERASE /dev/nvme0n1' "$balerion_state")
grep -q 'Configuration  Balerion' <<<"$balerion_output"
grep -q 'Disk           /dev/nvme0n1' <<<"$balerion_output"
grep -q 'Serial         NVME-PRIMARY' <<<"$balerion_output"
grep -q 'Preview complete. No disks were changed.' <<<"$balerion_output"
assert_no_secrets "$balerion_state"

bonhart_state="$scratch/bonhart-state"
bonhart_output=$(run_preview bonhart /dev/nvme0n1 'ERASE /dev/nvme0n1' "$bonhart_state")
grep -q 'Configuration  Bonhart' <<<"$bonhart_output"
grep -q 'Sudo policy    Separate administrator password' <<<"$bonhart_output"
assert_no_secrets "$bonhart_state"

excluded_state="$scratch/excluded-state"
if run_preview balerion /dev/sda 'ERASE /dev/sda' "$excluded_state" > "$scratch/excluded.out" 2>&1; then
  printf 'Installer disk exclusion unexpectedly succeeded.\n' >&2
  exit 1
fi
grep -q 'The requested disk is not eligible: /dev/sda' "$scratch/excluded.out"
assert_no_secrets "$excluded_state"

small_state="$scratch/small-state"
if run_preview bonhart /dev/nvme1n1 'ERASE /dev/nvme1n1' "$small_state" > "$scratch/small.out" 2>&1; then
  printf 'Bonhart minimum disk check unexpectedly succeeded.\n' >&2
  exit 1
fi
grep -q 'The requested disk is not eligible: /dev/nvme1n1' "$scratch/small.out"
assert_no_secrets "$small_state"

confirmation_state="$scratch/confirmation-state"
if run_preview balerion /dev/nvme0n1 'ERASE /dev/sdb' "$confirmation_state" > "$scratch/confirmation.out" 2>&1; then
  printf 'Incorrect erase confirmation unexpectedly succeeded.\n' >&2
  exit 1
fi
grep -q 'The erase confirmation did not match.' "$scratch/confirmation.out"
assert_no_secrets "$confirmation_state"

printf 'Installer preview tests passed.\n'
