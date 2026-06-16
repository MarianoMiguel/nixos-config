#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

if ! command -v nix >/dev/null 2>&1; then
  echo "nix is not installed. Install Nix or run this from an existing NixOS machine." >&2
  exit 1
fi

nix build .#installerIso
iso=$(find result/iso -maxdepth 1 -type f -name '*.iso' | sort | tail -n 1)

if [[ -z "${iso:-}" ]]; then
  echo "The ISO build completed, but no ISO was found under result/iso." >&2
  exit 1
fi

printf '%s\n' "$PWD/$iso"
