#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

matches=$(
  grep -RInE \
    'claudeTriage|claude-triage|claude-coredump-watch|OnFailure=claude-triage' \
    "$repo/flake.nix" "$repo/hosts" "$repo/modules" "$repo/profiles" \
    || true
)

if [[ -n $matches ]]; then
  printf 'Automatic AI crash triage is still configured:\n%s\n' "$matches" >&2
  exit 1
fi

printf 'Automatic AI crash triage is absent.\n'
