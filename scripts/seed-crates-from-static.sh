#!/usr/bin/env bash
set -uo pipefail

usage() {
  cat <<'USAGE'
Usage:
  seed-crates-from-static.sh --log BUILD_LOG
  seed-crates-from-static.sh --lock PATH [--lock PATH ...]

Fetches registry crate tarballs from static.crates.io and adds them to the Nix
store, so that Rust builds succeed on networks where crates.io's download API
(https://crates.io/api/v1/crates/<name>/<version>/download) answers 403.

overlays/crates-io-static-mirror.nix already fixes this for everything built
through this configuration's nixpkgs. This script exists for what an overlay
cannot reach: a flake that ships its own nixpkgs and that we consume through its
packages.<system> output, which is evaluated with its own overlays. It operates
on the store instead, below the flake boundary, so it works regardless of which
nixpkgs produced the derivation.

It is safe and idempotent. A fetchurl derivation is fixed-output, so its store
path depends only on (name, hash, hashMode). Adding a byte-identical tarball
under the same name therefore lands on exactly the path the build expects, and
Nix then treats that download as already done. A tarball whose contents do not
match lands on some other path and is ignored, so a wrong guess cannot corrupt
a build.

Modes:
  --log FILE    Seed only the crates a failed build actually asked for, read
                back from its log. Prefer this: it needs no knowledge of which
                flake or lock file was involved.
  --lock PATH   Seed every registry crate in a Cargo.lock. PATH may also be a
                directory, which is searched recursively for Cargo.lock files.

Environment:
  JOBS=n        Parallel downloads (default 16).
USAGE
}

mode=
declare -a lock_paths=()
log_file=

while (( $# > 0 )); do
  case $1 in
    -h|--help)
      usage
      exit 0
      ;;
    --log)
      mode=log
      log_file=${2:?--log needs a file}
      shift 2
      ;;
    --lock)
      mode=lock
      lock_paths+=("${2:?--lock needs a path}")
      shift 2
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z $mode ]]; then
  usage >&2
  exit 2
fi

for tool in curl sha256sum nix-store; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "$tool is required but not on PATH." >&2
    exit 1
  fi
done

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/dl"

# Split a store name like "crate-md-5-0.10.6.tar.gz" into crate and version.
# The regex is greedy, so it anchors on the *last* dash that begins a version;
# that keeps both digit-bearing crate names (md-5) and prerelease versions
# (1.0.0-beta.1) intact.
split_crate_name() {
  local stem=${1#crate-}
  stem=${stem%.tar.gz}
  [[ $stem =~ ^(.*)-([0-9].*)$ ]] || return 1
  printf '%s %s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
}

# Emit "crate version [expected-store-path]" lines for whatever needs seeding.
collect() {
  if [[ $mode == log ]]; then
    [[ -r $log_file ]] || { echo "Cannot read $log_file" >&2; exit 1; }
    local drv out sname pair
    while IFS= read -r drv; do
      out=$(nix-store --query --outputs "$drv" 2>/dev/null) || continue
      [[ -n $out && ! -e $out ]] || continue
      sname=${out##*/}
      sname=${sname#*-}
      pair=$(split_crate_name "$sname") || continue
      printf '%s %s\n' "$pair" "$out"
    done < <(grep -oE "/nix/store/[a-z0-9]{32}-crate-[^']*\.tar\.gz\.drv" \
               "$log_file" | sort -u)
  else
    local lock
    while IFS= read -r lock; do
      local name= version= checksum= expected=
      while IFS= read -r line; do
        case $line in
          'name = '*) name=${line#name = }; name=${name//\"/} ;;
          'version = '*) version=${line#version = }; version=${version//\"/} ;;
          # Only registry crates carry a checksum; path and git deps do not.
          # That checksum is the tarball's sha256, which is exactly what
          # fetchurl pins, so we can name the target path without guessing.
          'checksum = '*)
            checksum=${line#checksum = }
            checksum=${checksum//\"/}
            expected=$(nix-store --print-fixed-path sha256 "$checksum" \
              "crate-${name}-${version}.tar.gz" 2>/dev/null) || expected=
            printf '%s %s %s\n' "$name" "$version" "$expected"
            ;;
        esac
      done < "$lock"
    done < <(for path in "${lock_paths[@]}"; do
               if [[ -d $path ]]; then
                 find "$path" -name Cargo.lock
               else
                 printf '%s\n' "$path"
               fi
             done) | sort -u
  fi
}

seed_one() {
  local name=$1 version=$2 expected=${3:-}
  local sname="crate-${name}-${version}.tar.gz"
  local file="$work/dl/$sname"

  if [[ -n $expected && -e $expected ]]; then
    echo "HAVE $name-$version"
    return 0
  fi

  if ! curl -sSfL --retry 3 --retry-delay 1 \
        "https://static.crates.io/crates/${name}/${name}-${version}.crate" \
        -o "$file"; then
    echo "FAIL-DOWNLOAD $name-$version"
    return 1
  fi

  local added
  if ! added=$(nix-store --add-fixed sha256 "$file"); then
    echo "FAIL-ADD $name-$version"
    return 1
  fi
  rm -f "$file"

  # In log mode we know the path the build wants, so we can prove the tarball
  # was the right one rather than assuming it.
  if [[ -n $expected && $added != "$expected" ]]; then
    echo "FAIL-MISMATCH $name-$version wanted=$expected got=$added"
    return 1
  fi

  echo "ADDED $name-$version"
}
export -f seed_one split_crate_name
export work

collect > "$work/wanted.txt"
wanted=$(wc -l < "$work/wanted.txt")
if (( wanted == 0 )); then
  echo "Nothing to seed."
  exit 0
fi
echo "Seeding $wanted crate(s) from static.crates.io..." >&2

xargs -a "$work/wanted.txt" -P "${JOBS:-16}" -L 1 \
  bash -c 'seed_one "$@"' _ > "$work/result.log" 2>&1

added=$(grep -c '^ADDED' "$work/result.log")
have=$(grep -c '^HAVE' "$work/result.log")
failed=$(grep -c '^FAIL' "$work/result.log")
printf 'added: %s  already present: %s  failed: %s\n' "$added" "$have" "$failed"

if (( failed > 0 )); then
  grep '^FAIL' "$work/result.log" >&2
  exit 1
fi
