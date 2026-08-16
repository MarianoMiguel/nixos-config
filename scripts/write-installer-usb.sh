#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage:
  write-installer-usb.sh USB_DISK ISO [PAYLOAD.tar.zst ...]

Example:
  sudo ./scripts/write-installer-usb.sh /dev/disk/by-id/usb-General_USB_Disk_FC0301A76E537-0:0 result-installer/iso/mariano-nixos-balerion-installer.iso payload/*.tar.zst

This erases USB_DISK, writes the bootable NixOS ISO, then creates an exFAT
partition labeled MARIANOUSB in the remaining space for payload files.
USAGE
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  usage
  exit 0
fi

disk=${1:?$(usage)}
iso=${2:?$(usage)}
shift 2
payloads=("$@")
data_label=${DATA_LABEL:-MARIANOUSB}

if [[ $EUID -ne 0 ]]; then
  echo "Run as root." >&2
  exit 1
fi

if [[ ! -b "$disk" ]]; then
  echo "USB disk is not a block device: $disk" >&2
  exit 1
fi

if [[ ! -f "$iso" ]]; then
  echo "ISO does not exist: $iso" >&2
  exit 1
fi

removable=$(cat "/sys/class/block/$(basename "$(readlink -f "$disk")")/removable" 2>/dev/null || echo 0)
if [[ "$removable" != "1" && ${ALLOW_NON_REMOVABLE:-} != "1" ]]; then
  echo "$disk is not marked removable. Set ALLOW_NON_REMOVABLE=1 to override." >&2
  exit 1
fi

echo "About to erase USB disk:"
lsblk -o NAME,PATH,MODEL,SERIAL,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINTS "$disk"

if [[ ${YES:-} != "erase" ]]; then
  read -r -p "Type ERASE $disk to continue: " answer
  if [[ "$answer" != "ERASE $disk" ]]; then
    echo "Aborted." >&2
    exit 1
  fi
fi

while IFS= read -r mountpoint; do
  if [[ -n "$mountpoint" ]]; then
    umount -R "$mountpoint" 2>/dev/null || true
  fi
done < <(lsblk -nrpo MOUNTPOINTS "$disk" | tr ' ' '\n' | sort -r)

dd if="$iso" of="$disk" bs=4M status=progress conv=fsync
partprobe "$disk" || true
udevadm settle

disk_size_bytes=$(blockdev --getsize64 "$disk")
iso_size_bytes=$(stat -c '%s' "$iso")
start_mib=$(( (iso_size_bytes + 1048575) / 1048576 + 16 ))
end_mib=$(( disk_size_bytes / 1048576 - 1 ))

if (( end_mib > start_mib + 64 )); then
  start_sector=$(( start_mib * 2048 ))
  printf '%s,,7\n' "$start_sector" | sfdisk --append "$disk"
  partprobe "$disk" || true
  udevadm settle

  data_part=$(lsblk -ln -o PATH,TYPE "$disk" | awk '$2 == "part" { path=$1 } END { print path }')
  mkfs.exfat -n "$data_label" "$data_part"

  mount_dir=$(mktemp -d)
  cleanup_mount() {
    if mountpoint -q "$mount_dir"; then
      sync
      umount "$mount_dir"
    fi
    rmdir "$mount_dir" 2>/dev/null || true
  }
  trap cleanup_mount EXIT

  mount "$data_part" "$mount_dir"
  mkdir -p "$mount_dir/payload" "$mount_dir/scripts"

  for payload in "${payloads[@]}"; do
    if [[ -f "$payload" ]]; then
      cp -f "$payload" "$mount_dir/payload/"
    fi
  done

  cp -f "$(dirname "${BASH_SOURCE[0]}")/restore-personal-payload.sh" "$mount_dir/scripts/"
  sync
  umount "$mount_dir"
  rmdir "$mount_dir"
  trap - EXIT
else
  echo "No room left for a payload partition after writing the ISO." >&2
fi

sync
echo "USB installer is ready on $disk"
