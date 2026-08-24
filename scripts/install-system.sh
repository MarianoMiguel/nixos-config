#!/usr/bin/env bash
set -euo pipefail

readonly installer_user="mariano"
readonly state_dir="${INSTALLER_STATE_DIR:-/run/mariano-installer}"
readonly luks_password_file="$state_dir/luks-password"
readonly user_password_file="$state_dir/user-password"
readonly sudo_password_file="$state_dir/sudo-password"
readonly install_log="$state_dir/install.log"
readonly mount_root="/mnt/mariano-install"
readonly crypt_name="nixos-crypt"

preview=0
noninteractive=${INSTALLER_NONINTERACTIVE:-0}
crypt_partition=
boot_partition=
mounted_root=0
mounted_boot=0
opened_crypt=0
activated_vg=0

usage() {
  cat <<'USAGE'
Usage:
  install-system.sh [--preview]

Options:
  --preview  Run the complete wizard and stop before changing the selected disk.
  -h, --help Show this help.

The normal installer guides you through selecting Balerion or Bonhart, a target
disk, and separate LUKS, user, and administrator passwords. The selected disk
is completely erased after an exact confirmation prompt.
USAGE
}

cleanup() {
  set +e

  if (( mounted_boot )) && mountpoint -q "$mount_root/boot"; then
    umount "$mount_root/boot"
  fi
  if (( mounted_root )) && mountpoint -q "$mount_root"; then
    umount "$mount_root"
  fi
  if (( activated_vg )); then
    vgchange -an nixos >/dev/null 2>&1
  fi
  if (( opened_crypt )) && cryptsetup status "$crypt_name" >/dev/null 2>&1; then
    cryptsetup close "$crypt_name"
  fi

  rm -f "$luks_password_file" "$user_password_file" "$sudo_password_file"
}

abort_install() {
  trap - EXIT INT TERM
  cleanup
  exit 130
}

trap cleanup EXIT
trap abort_install INT TERM

die() {
  local message=$1

  if command -v gum >/dev/null 2>&1 && [[ -t 1 ]]; then
    gum style --foreground 196 --bold "Installation stopped" "$message" >&2
  else
    printf 'Installation stopped: %s\n' "$message" >&2
  fi
  exit 1
}

need_command() {
  command -v "$1" >/dev/null 2>&1 || die "Required command is missing: $1"
}

terminal_width() {
  local columns

  columns=$(tput cols 2>/dev/null || printf '80')
  if (( columns < 52 )); then
    printf '%s\n' "$columns"
  elif (( columns > 82 )); then
    printf '78\n'
  else
    printf '%s\n' "$((columns - 4))"
  fi
}

render_header() {
  local width

  width=$(terminal_width)
  clear
  gum style \
    --border double \
    --border-foreground 99 \
    --foreground 212 \
    --align center \
    --bold \
    --width "$width" \
    --padding "1 2" \
    "MARIANO NIXOS" \
    "Guided encrypted workstation installer"
  printf '\n'
}

notice() {
  gum style --foreground 245 "$1"
}

success() {
  gum style --foreground 42 --bold "✓ $1"
}

human_size() {
  local bytes=$1

  numfmt --to=iec-i --suffix=B "$bytes"
}

installer_source_disk() {
  local source_device resolved parent_name

  if [[ -n ${INSTALLER_EXCLUDED_DISK:-} ]]; then
    readlink -f "$INSTALLER_EXCLUDED_DISK"
    return
  fi

  source_device=$(findmnt -nro SOURCE /iso 2>/dev/null || true)
  [[ -n $source_device ]] || return 0
  resolved=$(readlink -f "$source_device")

  while [[ -b $resolved ]]; do
    if [[ $(lsblk -dnro TYPE "$resolved" 2>/dev/null || true) == disk ]]; then
      printf '%s\n' "$resolved"
      return
    fi
    parent_name=$(lsblk -dnro PKNAME "$resolved" 2>/dev/null || true)
    [[ -n $parent_name ]] || return 0
    resolved="/dev/$parent_name"
  done
}

disk_inventory() {
  if [[ -n ${INSTALLER_LSBLK_JSON:-} ]]; then
    cat "$INSTALLER_LSBLK_JSON"
  else
    lsblk --json --bytes --nodeps \
      --output NAME,PATH,MODEL,SERIAL,SIZE,TYPE,RO,RM,TRAN
  fi
}

disk_rows() {
  local minimum_bytes=$1
  local excluded_disk=$2

  disk_inventory | jq -r \
    --arg excluded "$excluded_disk" \
    --argjson minimum "$minimum_bytes" '
      .blockdevices[]
      | select(.type == "disk")
      | select((.ro // false) == false or (.ro // 0) == 0)
      | select((.size // 0) >= $minimum)
      | select(.path != $excluded)
      | [
          .path,
          (.size | tostring),
          ((.model // "Unknown model") | gsub("[\\t\\r\\n]+"; " ") | sub(" +$"; "")),
          ((.serial // "No serial") | gsub("[\\t\\r\\n]+"; " ") | sub(" +$"; "")),
          (.tran // "unknown")
        ]
      | @tsv
    '
}

stable_disk_path() {
  local selected=$1
  local resolved candidate candidate_resolved

  resolved=$(readlink -f "$selected")
  if [[ ! -d /dev/disk/by-id ]]; then
    printf '%s\n' "$selected"
    return
  fi

  for candidate in /dev/disk/by-id/wwn-* /dev/disk/by-id/nvme-* /dev/disk/by-id/ata-* /dev/disk/by-id/usb-*; do
    [[ -L $candidate && $candidate != *-part* ]] || continue
    candidate_resolved=$(readlink -f "$candidate")
    if [[ $candidate_resolved == "$resolved" ]]; then
      printf '%s\n' "$candidate"
      return
    fi
  done

  printf '%s\n' "$selected"
}

target_partition() {
  local label=$1

  lsblk --paths --raw --noheadings --output PATH,PARTLABEL "$disk_kernel_path" |
    awk -v label="$label" '$2 == label { print $1; exit }'
}

choose_configuration() {
  local choice

  if (( noninteractive )); then
    configuration=${INSTALLER_CONFIGURATION:?INSTALLER_CONFIGURATION is required in noninteractive mode}
  else
    render_header
    notice "Choose the hardware configuration for this machine."
    printf '\n'
    choice=$(
      printf '%s\n' \
        "Balerion  · Intel 13900KF + RTX 3080 Ti" \
        "Bonhart   · AMD laptop + 64 GiB hibernation swap" |
        gum choose --header "Machine configuration" --cursor.foreground 212
    ) || die "No configuration selected."

    case $choice in
      Balerion*) configuration=balerion ;;
      Bonhart*) configuration=bonhart ;;
      *) die "Unknown configuration selection." ;;
    esac
  fi

  case $configuration in
    balerion)
      minimum_disk_bytes=$((64 * 1024 * 1024 * 1024))
      configuration_label="Balerion"
      ;;
    bonhart)
      minimum_disk_bytes=$((96 * 1024 * 1024 * 1024))
      configuration_label="Bonhart"
      ;;
    *) die "Configuration must be balerion or bonhart." ;;
  esac
}

choose_disk() {
  local excluded rows display_rows selected_display selected_path size model _serial transport

  excluded=$(installer_source_disk || true)
  rows=$(disk_rows "$minimum_disk_bytes" "$excluded")
  [[ -n $rows ]] || die "No eligible disk is large enough for $configuration_label."

  if (( noninteractive )); then
    selected_path=${INSTALLER_DISK:?INSTALLER_DISK is required in noninteractive mode}
    selected_path=$(readlink -f "$selected_path")
    if ! awk -F '\t' -v selected="$selected_path" '$1 == selected { found = 1 } END { exit !found }' <<<"$rows"; then
      die "The requested disk is not eligible: $selected_path"
    fi
  else
    render_header
    notice "Choose the whole disk to erase. The installer USB is excluded."
    printf '\n'
    display_rows=$(
      while IFS=$'\t' read -r selected_path size model _serial transport; do
        printf '%s  ·  %s  ·  %s  ·  %s\n' \
          "$selected_path" "$(human_size "$size")" "$model" "$transport"
      done <<<"$rows"
    )
    selected_display=$(gum choose --header "Installation disk" --cursor.foreground 212 <<<"$display_rows") ||
      die "No installation disk selected."
    selected_path=${selected_display%%  ·  *}
  fi

  IFS=$'\t' read -r disk_kernel_path disk_size_bytes disk_model disk_serial disk_transport < <(
    awk -F '\t' -v selected="$selected_path" '$1 == selected { print; exit }' <<<"$rows"
  )
  [[ -n ${disk_kernel_path:-} ]] || die "Could not resolve the selected disk."

  disk_path=$(stable_disk_path "$disk_kernel_path")
  disk_size=$(human_size "$disk_size_bytes")
}

read_secret() {
  local source_file=$1
  local secret

  [[ -f $source_file ]] || die "Secret file does not exist: $source_file"
  IFS= read -r secret < "$source_file" || true
  printf '%s' "$secret"
}

prompt_password_pair() {
  local title=$1
  local description=$2
  local destination=$3
  local supplied_file=${4:-}
  local first second validation_message=

  if (( noninteractive )); then
    [[ -n $supplied_file ]] || die "$title requires a password file in noninteractive mode."
    first=$(read_secret "$supplied_file")
  else
    while true; do
      render_header
      notice "$description"
      if [[ -n $validation_message ]]; then
        printf '\n'
        gum style --foreground 196 --bold "$validation_message"
      fi
      printf '\n'
      first=$(gum input --password --prompt "$title › " --prompt.foreground 212) ||
        die "$title entry cancelled."

      if (( ${#first} < 8 )); then
        validation_message="Use at least 8 characters."
        continue
      fi

      second=$(gum input --password --prompt "Confirm › " --prompt.foreground 212) ||
        die "$title confirmation cancelled."

      if [[ $first != "$second" ]]; then
        validation_message="The passwords did not match. Try again."
        continue
      fi

      break
    done
  fi

  (( ${#first} >= 8 )) || die "$title must contain at least 8 characters."
  umask 077
  printf '%s' "$first" > "$destination"
  unset first second
}

preflight_environment() {
  (( preview )) && return

  (( EUID == 0 )) || die "Run the installer as root."
  [[ -d /sys/firmware/efi/efivars ]] || die "Boot the USB installer in UEFI mode."

  need_command cryptsetup
  need_command disko-install
  need_command findmnt
  need_command nixos-enter
  need_command rsync
  need_command udevadm
  need_command vgchange
}

preflight_target() {
  (( preview )) && return

  [[ -b $disk_kernel_path ]] || die "The selected target is no longer a block device."
}

collect_passwords() {
  prompt_password_pair \
    "LUKS password" \
    "This password unlocks the encrypted disk before NixOS starts." \
    "$luks_password_file" \
    "${INSTALLER_LUKS_PASSWORD_FILE:-}"

  prompt_password_pair \
    "User password" \
    "This password signs in to Mariano's desktop account." \
    "$user_password_file" \
    "${INSTALLER_USER_PASSWORD_FILE:-}"

  prompt_password_pair \
    "Administrator password" \
    "This separate root password is required whenever sudo asks to continue." \
    "$sudo_password_file" \
    "${INSTALLER_SUDO_PASSWORD_FILE:-}"
}

show_summary() {
  local width confirmation expected_confirmation

  width=$(terminal_width)
  expected_confirmation="ERASE $disk_kernel_path"

  clear
  gum style --foreground 212 --bold "MARIANO NIXOS  ·  Final confirmation"
  printf '\n'
  gum style \
    --border rounded \
    --border-foreground 99 \
    --width "$width" \
    --padding "1 2" \
    "Ready to install" \
    "" \
    "Configuration  $configuration_label" \
    "Disk           $disk_kernel_path" \
    "Size           $disk_size" \
    "Model          $disk_model" \
    "Serial         $disk_serial" \
    "Connection     $disk_transport" \
    "Encryption     LUKS2" \
    "Login user     $installer_user" \
    "Sudo policy    Separate administrator password"
  printf '\n'
  gum style --foreground 196 --bold "Everything on $disk_kernel_path will be permanently erased."
  printf '\n'

  if (( noninteractive )); then
    confirmation=${INSTALLER_CONFIRMATION:-}
  else
    confirmation=$(gum input \
      --placeholder "$expected_confirmation" \
      --prompt "Type the phrase exactly › " \
      --prompt.foreground 212) || die "Confirmation cancelled."
  fi

  [[ $confirmation == "$expected_confirmation" ]] || die "The erase confirmation did not match."
}

run_logged() {
  local title=$1
  local child_program="exec \"\$@\" >>\"\$INSTALLER_LOG_FILE\" 2>&1"
  shift

  if declare -F "$1" >/dev/null 2>&1; then
    if ! "$@" >> "$install_log" 2>&1; then
      tail -n 40 "$install_log" >&2
      die "$title failed."
    fi
    if (( !noninteractive )) && [[ -t 1 ]]; then
      success "$title"
    fi
  elif (( noninteractive )) || [[ ! -t 1 ]]; then
    printf '%s...\n' "$title"
    if ! "$@" >> "$install_log" 2>&1; then
      tail -n 40 "$install_log" >&2
      die "$title failed."
    fi
  elif ! gum spin --spinner dot --title "$title" -- \
    env INSTALLER_LOG_FILE="$install_log" bash -c "$child_program" _ "$@"; then
    gum style --foreground 196 --bold "$title failed."
    tail -n 40 "$install_log" >&2
    die "The detailed log is at $install_log."
  else
    success "$title"
  fi
}

open_installed_system() {
  udevadm settle
  crypt_partition=$(target_partition NIXOS-CRYPT)
  boot_partition=$(target_partition NIXOS-BOOT)
  [[ -b $crypt_partition ]] || die "Encrypted partition was not created."
  [[ -b $boot_partition ]] || die "Boot partition was not created."

  if ! cryptsetup status "$crypt_name" >/dev/null 2>&1; then
    cryptsetup open --key-file "$luks_password_file" "$crypt_partition" "$crypt_name" \
      >> "$install_log" 2>&1
  fi
  opened_crypt=1

  if [[ $configuration == bonhart ]]; then
    vgchange -ay nixos >> "$install_log" 2>&1
    activated_vg=1
    root_device=/dev/nixos/root
  else
    root_device="/dev/mapper/$crypt_name"
  fi

  mkdir -p "$mount_root"
  mount "$root_device" "$mount_root"
  mounted_root=1
  mkdir -p "$mount_root/boot"
  mount "$boot_partition" "$mount_root/boot"
  mounted_boot=1
}

persist_configuration() {
  local config_source=${INSTALLER_CONFIG_SOURCE:-/etc/nixos-config}
  local target_config="$mount_root/etc/nixos"

  [[ -f $config_source/flake.nix ]] || die "Installer configuration source is missing."
  mkdir -p "$target_config"
  rsync -a --delete "$config_source/" "$target_config/"
  cp \
    "$config_source/hosts/$configuration/storage-encrypted.nix" \
    "$target_config/hosts/$configuration/storage.nix"
}

set_installed_passwords() {
  local root_hash user_hash

  user_hash=$(openssl passwd -6 -stdin < "$user_password_file")
  root_hash=$(openssl passwd -6 -stdin < "$sudo_password_file")
  {
    printf '%s:%s\n' "$installer_user" "$user_hash"
    printf 'root:%s\n' "$root_hash"
  } | nixos-enter --root "$mount_root" -c 'chpasswd -e' >> "$install_log" 2>&1
  unset root_hash user_hash
}

verify_installation() {
  local user_shadow root_shadow

  cryptsetup isLuks "$crypt_partition" || die "LUKS verification failed."
  [[ -x $mount_root/nix/var/nix/profiles/system/init ]] ||
    die "The installed NixOS system profile is incomplete."
  [[ -f $mount_root/etc/nixos/hosts/$configuration/storage.nix ]] ||
    die "The persistent encrypted-storage configuration is missing."
  find "$mount_root/boot/EFI" -type f -iname '*.efi' -print -quit | grep -q . ||
    die "No EFI boot loader was installed."

  user_shadow=$(nixos-enter --root "$mount_root" -c "getent shadow $installer_user" | cut -d: -f2 || true)
  root_shadow=$(nixos-enter --root "$mount_root" -c 'getent shadow root' | cut -d: -f2 || true)
  [[ -n $user_shadow && $user_shadow != '!'* ]] ||
    die "The user password was not installed."
  [[ -n $root_shadow && $root_shadow != '!'* ]] ||
    die "The administrator password was not installed."

  install -Dm0600 "$install_log" "$mount_root/var/log/mariano-installer.log"
}

install_system() {
  local flake_source=${INSTALLER_FLAKE_SOURCE:?INSTALLER_FLAKE_SOURCE is not set}
  local flake_reference="$flake_source#$configuration-install"

  render_header
  notice "The installer is now working from the pinned, offline system image."
  printf '\n'

  run_logged \
    "Partitioning, encrypting, and installing $configuration_label" \
    disko-install \
      --flake "$flake_reference" \
      --disk main "$disk_path" \
      --mount-point /mnt/disko-install-root \
      --write-efi-boot-entries \
      --option offline true

  run_logged "Opening the installed system for final setup" open_installed_system
  run_logged "Saving the pinned configuration" persist_configuration
  run_logged "Setting login and administrator passwords" set_installed_passwords
  run_logged "Verifying encryption, boot files, and accounts" verify_installation

  cleanup
  trap - EXIT INT TERM

  render_header
  gum style \
    --border rounded \
    --border-foreground 42 \
    --foreground 42 \
    --bold \
    --padding "1 2" \
    "Installation complete" \
    "" \
    "$configuration_label is encrypted, installed, and verified." \
    "Remove the USB drive, then reboot."
}

main() {
  while (( $# > 0 )); do
    case $1 in
      --preview) preview=1 ;;
      -h | --help)
        usage
        exit 0
        ;;
      *)
        usage >&2
        exit 2
        ;;
    esac
    shift
  done

  need_command jq
  need_command gum
  need_command lsblk
  need_command numfmt

  preflight_environment

  mkdir -p "$state_dir"
  chmod 0700 "$state_dir"
  : > "$install_log"
  chmod 0600 "$install_log"

  choose_configuration
  choose_disk
  preflight_target
  collect_passwords
  show_summary

  if (( preview )); then
    printf '\n'
    success "Preview complete. No disks were changed."
    exit 0
  fi

  install_system
}

main "$@"
