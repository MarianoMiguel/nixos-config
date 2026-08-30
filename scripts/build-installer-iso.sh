#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  build-installer-iso.sh [--host balerion|bonhart|both]

Validates the encrypted install targets, then builds a graphical installer ISO
containing the literal current workspace snapshot.

--host both (the default) embeds the offline closures for both machines.
Naming one machine builds an image with only that machine's closure: about
half the build time, half the ISO, and half the USB write.

Environment:
  SKIP_VALIDATION=1      Build only the ISO.
  SKIP_SPACE_CHECK=1     Skip the free-disk-space preflight.
  REQUIRED_FREE_GIB=n    Free space required by the preflight
                         (default 40, or 25 for a single-host image).
  OUT_LINK=path          Use a result link other than result-installer.
USAGE
}

host=both
while (( $# > 0 )); do
  case $1 in
    -h|--help)
      usage
      exit 0
      ;;
    --host)
      host=${2:?--host needs a value}
      shift 2
      ;;
    --host=*)
      host=${1#--host=}
      shift
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

case $host in
  both)
    iso_attribute=installerIso
    install_targets=(balerion-install bonhart-install)
    default_free_gib=40
    ;;
  balerion)
    iso_attribute=installerIsoBalerion
    install_targets=(balerion-install)
    default_free_gib=25
    ;;
  bonhart)
    iso_attribute=installerIsoBonhart
    install_targets=(bonhart-install)
    default_free_gib=25
    ;;
  *)
    echo "--host must be balerion, bonhart, or both (got: $host)" >&2
    exit 2
    ;;
esac

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo"

if ! command -v nix >/dev/null 2>&1; then
  echo "nix is not installed. Install Nix or run this from an existing NixOS machine." >&2
  exit 1
fi

flake="path:$repo"
out_link=${OUT_LINK:-result-installer}

# The ISO embeds complete workstation closures, so the build needs tens of
# gibibytes in the store and for the squashfs scratch space. Running out
# mid-build wastes an hour and leaves confusing partial state; fail up front
# instead.
if [[ ${SKIP_SPACE_CHECK:-0} != 1 ]]; then
  required_gib=${REQUIRED_FREE_GIB:-$default_free_gib}
  for location in /nix/store "${TMPDIR:-/tmp}"; do
    [[ -d $location ]] || continue
    available_bytes=$(df --output=avail --block-size=1 "$location" | tail -n 1)
    if (( available_bytes < required_gib * 1024 * 1024 * 1024 )); then
      echo "Only $(numfmt --to=iec-i --suffix=B "$available_bytes") is free at $location; the ISO build needs about ${required_gib}GiB." >&2
      echo "Free up space, or set SKIP_SPACE_CHECK=1 / REQUIRED_FREE_GIB=n to override." >&2
      exit 1
    fi
  done
fi

if [[ ${SKIP_VALIDATION:-0} != 1 ]]; then
  echo "Evaluating every flake output..." >&2
  nix flake check --no-build "$flake"

  # Build only the systems this image will actually embed. Everything is
  # needed by the ISO anyway, so this work is never wasted; doing it first
  # gives clear per-system progress and errors.
  for configuration in "${install_targets[@]}"; do
    echo "Building $configuration..." >&2
    nix build --no-link \
      "$flake#nixosConfigurations.$configuration.config.system.build.toplevel"
  done
fi

echo "Building the installer from the current workspace snapshot..." >&2
nix build --out-link "$out_link" "$flake#$iso_attribute"
iso=$(find "$out_link/iso" -maxdepth 1 -type f -name '*.iso' | sort | tail -n 1)

if [[ -z "${iso:-}" ]]; then
  echo "The ISO build completed, but no ISO was found under $out_link/iso." >&2
  exit 1
fi

echo "ISO size: $(numfmt --to=iec-i --suffix=B "$(stat -c '%s' "$iso")")" >&2
realpath "$iso"
