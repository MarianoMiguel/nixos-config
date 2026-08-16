#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
endpoint="${GRANOLA_DOWNLOAD_ENDPOINT:-https://api.granola.ai/v1/download-latest-windows}"
windows_user_agent='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36'

for command_name in curl jq nix; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "$command_name" >&2
    exit 1
  fi
done

url="$(
  curl -fsSIL \
    -A "$windows_user_agent" \
    -H 'sec-ch-ua-platform: "Windows"' \
    "$endpoint" \
    | awk 'tolower($1) == "location:" { print $2 }' \
    | tr -d '\r' \
    | tail -n 1
)"

if [[ ! "$url" =~ /([0-9]+\.[0-9]+\.[0-9]+)/Granola-([0-9]+\.[0-9]+\.[0-9]+)-win-x64\.exe$ ]]; then
  printf 'Unexpected Granola download URL: %s\n' "$url" >&2
  exit 1
fi

version="${BASH_REMATCH[1]}"
if [[ "$version" != "${BASH_REMATCH[2]}" ]]; then
  printf 'Granola version mismatch in download URL: %s\n' "$url" >&2
  exit 1
fi

hash="$(nix store prefetch-file --json "$url" | jq -er .hash)"
tmp="$(mktemp "$script_dir/source.json.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

jq -n \
  --arg version "$version" \
  --arg url "$url" \
  --arg hash "$hash" \
  '{version: $version, url: $url, hash: $hash}' > "$tmp"
mv "$tmp" "$script_dir/source.json"
trap - EXIT

printf 'Pinned Granola %s (%s)\n' "$version" "$hash"
printf 'Validate with: nix build --no-link path:%s#granola -L\n' "$(cd "$script_dir/../.." && pwd)"
