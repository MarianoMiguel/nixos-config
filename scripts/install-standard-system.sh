#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage:
  install-standard-system.sh TARGET_DISK [hostname]
  install-balerion TARGET_DISK

Example:
  install-standard-system.sh /dev/disk/by-id/nvme-Samsung_... mariano-laptop

This erases TARGET_DISK and installs the #standard NixOS config with:
  - UEFI systemd-boot
  - FAT32 /boot labeled BOOT
  - ext4 / labeled NIXOS
  - no LUKS and no YubiKey requirement

Set NIXOS_CONFIGURATION=balerion to install the hardware-specific #balerion
configuration with the same BOOT and NIXOS filesystem labels.

The custom installer ISO provides `install-balerion` as the preferred shortcut
for the gaming PC.
USAGE
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  usage
  exit 0
fi

disk=${1:?$(usage)}
hostname=${2:-nixos-dev}
repo=${NIXOS_CONFIG:-/etc/nixos-config}
configuration=${NIXOS_CONFIGURATION:-standard}

if [[ $EUID -ne 0 ]]; then
  echo "Run as root from the NixOS installer." >&2
  exit 1
fi

if [[ ! -b "$disk" ]]; then
  echo "Target is not a block device: $disk" >&2
  exit 1
fi

if [[ ! "$hostname" =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,62}$ ]]; then
  echo "Invalid hostname: $hostname" >&2
  exit 1
fi

if [[ ! "$configuration" =~ ^[A-Za-z0-9][A-Za-z0-9_-]{0,62}$ ]]; then
  echo "Invalid NixOS configuration: $configuration" >&2
  exit 1
fi

if [[ ! -f "$repo/flake.nix" ]]; then
  echo "NixOS config repo not found at $repo. Set NIXOS_CONFIG=/path/to/repo." >&2
  exit 1
fi

if ! nix eval --raw "path:$repo#nixosConfigurations.$configuration.config.networking.hostName" >/dev/null; then
  echo "NixOS configuration not found or invalid: $configuration" >&2
  exit 1
fi

echo "About to erase and install NixOS on:"
lsblk -o NAME,PATH,MODEL,SERIAL,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINTS "$disk"

if [[ ${YES:-} != "erase" ]]; then
  read -r -p "Type ERASE $disk to continue: " answer
  if [[ "$answer" != "ERASE $disk" ]]; then
    echo "Aborted." >&2
    exit 1
  fi
fi

partition_path() {
  local base=$1
  local number=$2

  if [[ "$base" == /dev/disk/by-id/* || "$base" == /dev/disk/by-path/* ]]; then
    printf '%s-part%s\n' "$base" "$number"
  elif [[ "$base" =~ [0-9]$ ]]; then
    printf '%sp%s\n' "$base" "$number"
  else
    printf '%s%s\n' "$base" "$number"
  fi
}

boot_part=$(partition_path "$disk" 1)
root_part=$(partition_path "$disk" 2)

swapoff --all || true
umount -R /mnt 2>/dev/null || true

wipefs --all --force "$disk"
sgdisk --zap-all "$disk"
parted --script "$disk" \
  mklabel gpt \
  mkpart ESP fat32 1MiB 1025MiB \
  set 1 esp on \
  mkpart nixos ext4 1025MiB 100%
partprobe "$disk"
udevadm settle

mkfs.vfat -F 32 -n BOOT "$boot_part"
mkfs.ext4 -F -L NIXOS "$root_part"

mount "$root_part" /mnt
mkdir -p /mnt/boot /mnt/etc
mount "$boot_part" /mnt/boot

rsync -a --delete "$repo/" /mnt/etc/nixos/

if [[ "$configuration" == standard ]]; then
  cat > /mnt/etc/nixos/hosts/standard/local.nix <<EOF
{ ... }:

{
  networking.hostName = "$hostname";
}
EOF
fi

nixos-install --flake "path:/mnt/etc/nixos#$configuration" --no-root-passwd

echo "Install finished. Set Mariano's password with passwd mariano after reboot if needed."
