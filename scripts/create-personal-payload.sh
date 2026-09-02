#!/usr/bin/env bash
set -euo pipefail

# The installer USB's payload partition is exFAT, which has no permission
# bits, and the archive holds SSH private keys and API tokens. So the archive
# is encrypted with an age passphrase before it touches disk, and everything
# this script writes is private to the invoking user.
umask 077

destination=${1:-"$HOME/nixos-usb-payload"}
timestamp=$(date -u +%Y%m%dT%H%M%SZ)
payload="$destination/mariano-personal-payload-$timestamp.tar.zst.age"
manifest="$destination/mariano-personal-payload-$timestamp.manifest.txt"

for tool in age tar zstd; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Missing required tool: $tool" >&2
    exit 1
  fi
done

mkdir -p "$destination"

home_real=$(realpath -m "$HOME")
destination_real=$(realpath -m "$destination")
payload_real=$(realpath -m "$payload")
manifest_real=$(realpath -m "$manifest")

tar_excludes=()
for output_path in "$destination_real" "$payload_real" "$manifest_real"; do
  if [[ "$output_path" == "$home_real/"* ]]; then
    tar_excludes+=(--exclude="${output_path#"$home_real/"}")
  fi
done

tar_excludes+=(
  --exclude=node_modules
  --exclude='*/node_modules'
  --exclude='*/node_modules/*'
)

paths=(
  Development
  .ssh
  .gitconfig
  .nvm
  .npm
  .config/gh
  .config/git
  .config/Code/User/globalStorage
  .config/Slack
  .config/slack
  .config/Codex
  .codex
  .claude
)

existing=()
for path in "${paths[@]}"; do
  if [[ -e "$HOME/$path" ]]; then
    existing+=("$path")
  fi
done

if [[ ${#existing[@]} -eq 0 ]]; then
  echo "No payload paths were found under $HOME." >&2
  exit 1
fi

{
  echo "Created: $timestamp"
  echo "Source home: $HOME"
  echo "Destination: $destination_real"
  echo "Excluded: node_modules directories"
  echo "Encryption: age passphrase (restore-personal-payload.sh asks for it)"
  echo "Payload contains private data, including SSH keys if .ssh exists."
  printf '%s\n' "${existing[@]}"
} > "$manifest"

echo "Choose the payload passphrase. It is the only way to read this archive." >&2
tar \
  --create \
  --ignore-failed-read \
  --warning=no-file-changed \
  --xattrs \
  --acls \
  --preserve-permissions \
  --directory "$HOME" \
  "${tar_excludes[@]}" \
  "${existing[@]}" \
  | zstd -T0 -10 \
  | age --passphrase --output "$payload"

printf '%s\n' "$payload"
printf '%s\n' "$manifest"
