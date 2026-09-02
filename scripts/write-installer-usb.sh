#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage:
  write-installer-usb.sh [USB_DISK] [ISO] [PAYLOAD.tar.zst.age ...]

Examples:
  sudo ./scripts/write-installer-usb.sh
  sudo ./scripts/write-installer-usb.sh /dev/disk/by-id/usb-General_USB_Disk_FC0301A76E537-0:0 result-installer/iso/mariano-nixos-installer.iso payload/*.tar.zst.age

With no USB_DISK (or "auto"), removable disks are listed and one is chosen
interactively. With no ISO (or "auto"), the newest ISO under
result-installer/iso/ is used.

This erases USB_DISK, writes the bootable NixOS ISO, then creates an exFAT
partition labeled MARIANOUSB in the remaining space for payload files.
USAGE
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  usage
  exit 0
fi

disk=${1:-auto}
iso=${2:-auto}
if (( $# >= 2 )); then
  shift 2
elif (( $# == 1 )); then
  shift 1
fi
payloads=("$@")
data_label=${DATA_LABEL:-MARIANOUSB}

if [[ $EUID -ne 0 ]]; then
  echo "Run as root." >&2
  exit 1
fi

if [[ $iso == auto ]]; then
  repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
  iso=$(find "$repo/result-installer/iso" -maxdepth 1 -type f -name '*.iso' 2>/dev/null | sort | tail -n 1 || true)
  if [[ -z $iso ]]; then
    echo "No ISO found under result-installer/iso/. Build one with ./scripts/build-installer-iso.sh or pass the ISO path." >&2
    exit 1
  fi
  echo "Using ISO: $iso"
fi

if [[ ! -f "$iso" ]]; then
  echo "ISO does not exist: $iso" >&2
  exit 1
fi

if [[ $disk == auto ]]; then
  mapfile -t candidates < <(lsblk --nodeps --noheadings --raw --output PATH,RM,RO | awk '$2 == 1 && $3 == 0 { print $1 }')
  if (( ${#candidates[@]} == 0 )); then
    echo "No removable disks were found. Insert the USB drive, or pass the disk path explicitly." >&2
    exit 1
  fi

  echo "Removable disks:"
  for i in "${!candidates[@]}"; do
    description=$(lsblk --nodeps --noheadings --output MODEL,SIZE,TRAN "${candidates[$i]}" | sed 's/  */  /g')
    printf '%3d) %s  %s\n' "$((i + 1))" "${candidates[$i]}" "$description"
  done
  read -r -p "Number of the disk to ERASE: " selection
  if ! [[ $selection =~ ^[0-9]+$ ]] || (( selection < 1 || selection > ${#candidates[@]} )); then
    echo "Invalid selection." >&2
    exit 1
  fi
  disk=${candidates[$((selection - 1))]}
fi

if [[ ! -b "$disk" ]]; then
  echo "USB disk is not a block device: $disk" >&2
  exit 1
fi

removable=$(cat "/sys/class/block/$(basename "$(readlink -f "$disk")")/removable" 2>/dev/null || echo 0)
if [[ "$removable" != "1" && ${ALLOW_NON_REMOVABLE:-} != "1" ]]; then
  echo "$disk is not marked removable. Set ALLOW_NON_REMOVABLE=1 to override." >&2
  exit 1
fi

disk_size_bytes=$(blockdev --getsize64 "$disk")
iso_size_bytes=$(stat -c '%s' "$iso")
if (( iso_size_bytes + 64 * 1024 * 1024 > disk_size_bytes )); then
  echo "The ISO ($(numfmt --to=iec-i --suffix=B "$iso_size_bytes")) does not fit on $disk ($(numfmt --to=iec-i --suffix=B "$disk_size_bytes"))." >&2
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

# Read the image back and compare before touching the partition table. A
# truncated copy or a failing/fake-capacity stick otherwise boots into an
# installer whose offline payload is silently incomplete, which the wizard
# only catches at the last gate before erasing a disk. Drop the page cache
# first so the comparison reads the device, not the bytes cached during dd.
if [[ ${SKIP_VERIFY:-} != 1 ]]; then
  echo "Verifying the written image ($(numfmt --to=iec-i --suffix=B "$iso_size_bytes") read back)..."
  sync
  echo 3 > /proc/sys/vm/drop_caches
  if ! cmp -n "$iso_size_bytes" "$iso" "$disk"; then
    echo "The USB contents do not match the ISO. The drive may be failing or lying about its capacity; try another stick or port, or rerun with SKIP_VERIFY=1 to accept the risk." >&2
    exit 1
  fi
fi

partprobe "$disk" || true
udevadm settle

start_mib=$(( (iso_size_bytes + 1048575) / 1048576 + 16 ))
end_mib=$(( disk_size_bytes / 1048576 - 1 ))

if (( end_mib > start_mib + 64 )); then
  partitions_before=$(lsblk -ln -o PATH,TYPE "$disk" | awk '$2 == "part" { print $1 }')
  start_sector=$(( start_mib * 2048 ))
  printf '%s,,7\n' "$start_sector" | sfdisk --append "$disk"
  partprobe "$disk" || true
  udevadm settle

  data_part=$(comm -13 \
    <(sort <<<"$partitions_before") \
    <(lsblk -ln -o PATH,TYPE "$disk" | awk '$2 == "part" { print $1 }' | sort))
  if [[ -z "$data_part" || $(wc -l <<<"$data_part") -ne 1 ]]; then
    echo "Could not identify the appended payload partition on $disk." >&2
    exit 1
  fi
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
