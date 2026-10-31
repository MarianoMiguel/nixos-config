#!/usr/bin/env bash
# scripts/system-update.sh (Update All) against a scratch checkout: it refuses
# uncommitted or untracked code, commits the new flake.lock, builds exactly
# that commit from git, lists the commits since the deployed generation, and
# undoes its lock commit when the build or the switch fails.
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

fake_bin=$scratch/bin
checkout=$scratch/checkout
export HOME=$scratch/home
export GIT_CONFIG_NOSYSTEM=1
export FAKE_LOG=$scratch/calls.log
export FAKE_STORE=$scratch/store
export FAKE_PROFILE=$scratch/profile
export FAKE_CURRENT=$scratch/current
mkdir -p "$fake_bin" "$HOME" "$FAKE_STORE" "$checkout/hosts/bonhart" "$checkout/hosts/other"
user=$(id -un)

cat > "$fake_bin/runuser" <<'EOF'
#!/usr/bin/env bash
while [[ $1 != -- ]]; do shift; done
shift
exec "$@"
EOF
cat > "$fake_bin/getent" <<'EOF'
#!/usr/bin/env bash
printf '%s:x:1000:100::%s:/bin/sh\n' "$2" "$HOME"
EOF
# nix flake update --flake REF --commit-lock-file --option commit-lock-file-summary SUMMARY
# nix build --out-link LINK REF#ATTR
cat > "$fake_bin/nix" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'nix %s\n' "$*" >> "$FAKE_LOG"
case $1 in
  flake)
    dir=${4#git+file://}
    case ${FAKE_UPDATE:-change} in
      none) ;;
      fail) echo half-written >> "$dir/flake.lock"; exit 1 ;;
      change)
        echo "update $RANDOM" >> "$dir/flake.lock"
        git -C "$dir" commit -q -m "$8" -- flake.lock
        ;;
    esac
    ;;
  build)
    [[ ${FAKE_BUILD:-ok} == ok ]] || exit 1
    ref=${4%%#*}
    rev=${ref##*rev=}
    system=$FAKE_STORE/system-$rev
    mkdir -p "$system/bin" "$system/sw/bin"
    printf '#!/usr/bin/env bash\n' > "$system/bin/switch-to-configuration"
    printf '#!/usr/bin/env bash\necho %s\n' "$rev" > "$system/sw/bin/nixos-version"
    chmod +x "$system/bin/switch-to-configuration" "$system/sw/bin/nixos-version"
    ln -sfn "$system" "$3"
    ;;
esac
EOF
cat > "$fake_bin/nixos-rebuild" <<'EOF'
#!/usr/bin/env bash
printf 'nixos-rebuild %s\n' "$*" >> "$FAKE_LOG"
system=${*: -1}
case ${FAKE_SWITCH:-ok} in
  ok) ln -sfn "$system" "$FAKE_PROFILE"; ln -sfn "$system" "$FAKE_CURRENT" ;;
  partial) ln -sfn "$system" "$FAKE_PROFILE"; exit 4 ;;
  fail) exit 1 ;;
esac
EOF
chmod +x "$fake_bin"/*

# A running system built from a folder: it records no commit.
mkdir -p "$scratch/unrecorded/sw/bin"
printf '#!/usr/bin/env bash\necho "configuration revision is unknown" >&2\nexit 1\n' \
  > "$scratch/unrecorded/sw/bin/nixos-version"
chmod +x "$scratch/unrecorded/sw/bin/nixos-version"
ln -sfn "$scratch/unrecorded" "$FAKE_CURRENT"

git_c() {
  git -C "$checkout" "$@"
}
git_c init -q
git_c config user.name Owner
git_c config user.email owner@example.com
printf '{ }\n' > "$checkout/flake.nix"
printf 'lock\n' > "$checkout/flake.lock"
printf '{ }\n' > "$checkout/hosts/bonhart/storage.nix"
printf 'hosts/*/storage.nix\n!hosts/bonhart/storage.nix\nresult\n' > "$checkout/.gitignore"
git_c add -A
git_c commit -qm "Initial configuration"
# Untracked files that are not .nix, and build results, do not matter.
printf 'notes\n' > "$checkout/notes.txt"
ln -s /nix/store/example-result "$checkout/result"
ln -sfn "$checkout" "$scratch/etc-nixos"

# run_update LINK: Update All with /etc/nixos at LINK; output in $output,
# exit status in $status.
run_update() {
  : > "$FAKE_LOG"
  status=0
  output=$(env PATH="$fake_bin:$PATH" SUDO_USER="$user" bash -c '
    host=testhost
    update_description="Updating all movable flake inputs..."
    commit_summary="flake.lock: update all inputs"
    update_inputs=()
    config_link=$1
    state_dir=$2
    current_system=$3
    system_profile=$4
    source "$5"
  ' _ "$1" "$scratch/state" "$FAKE_CURRENT" "$FAKE_PROFILE" "$repo/scripts/system-update.sh" 2>&1) || status=$?
}
fail() {
  printf 'FAIL: %s\n--- output\n%s\n--- calls\n' "$1" "$output" >&2
  cat "$FAKE_LOG" >&2
  exit 1
}
expect_refusal() {
  [[ $status != 0 ]] || fail "expected a refusal: $1"
  grep -Fq -- "$1" <<< "$output" || fail "missing message: $1"
  [[ ! -s $FAKE_LOG ]] || fail "nothing may be updated or built after a refusal"
}
expect_success() {
  [[ $status == 0 ]] || fail "expected success"
}
expect() {
  grep -Fq -- "$1" <<< "$output" || fail "missing: $1"
}
expect_clean() {
  [[ -z $(git_c status --porcelain --untracked-files=no) ]] || fail "the checkout must stay clean"
}
head_rev() {
  git_c rev-parse HEAD
}

# Not a git checkout.
mkdir -p "$scratch/plain"
printf 'lock\n' > "$scratch/plain/flake.lock"
ln -sfn "$scratch/plain" "$scratch/plain-link"
run_update "$scratch/plain-link"
expect_refusal "is not a git checkout"

# Uncommitted changes to a tracked file.
printf '{ x = 1; }\n' > "$checkout/flake.nix"
run_update "$scratch/etc-nixos"
expect_refusal "has uncommitted changes:"
expect " M flake.nix"
git_c checkout -q -- flake.nix

# An untracked .nix file would silently drop out of a git build.
printf '{ }\n' > "$checkout/hosts/other/local.nix"
run_update "$scratch/etc-nixos"
expect_refusal "untracked: hosts/other/local.nix"
rm "$checkout/hosts/other/local.nix"

# So would a git-ignored one, like another machine's installer-written storage.nix.
printf '{ }\n' > "$checkout/hosts/other/storage.nix"
run_update "$scratch/etc-nixos"
expect_refusal "ignored:   hosts/other/storage.nix"
rm "$checkout/hosts/other/storage.nix"

# A failed input update leaves flake.lock as committed.
before=$(head_rev)
FAKE_UPDATE=fail run_update "$scratch/etc-nixos"
[[ $status != 0 ]] || fail "a failed input update must fail"
expect "Input update failed"
[[ $(head_rev) == "$before" ]] || fail "a failed input update must not commit"
expect_clean

# Success, from a running system that records no commit.
run_update "$scratch/etc-nixos"
expect_success
first=$(head_rev)
[[ $first != "$before" ]] || fail "the new flake.lock must be committed"
[[ $(git_c log -1 --format=%s) == "flake.lock: update all inputs" ]] || fail "lock commit subject"
expect "Committed the new flake.lock as ${first:0:12}."
expect "does not record the commit it was built from"
grep -Fq "/system git+file://$checkout?rev=$first#nixosConfigurations.testhost.config.system.build.toplevel" "$FAKE_LOG" ||
  fail "the build must use git+file at the lock commit"
grep -Fq "nix flake update --flake git+file://$checkout --commit-lock-file" "$FAKE_LOG" ||
  fail "the input update must read the checkout through git"
grep -Fxq "nixos-rebuild switch --no-reexec --store-path $FAKE_STORE/system-$first" "$FAKE_LOG" ||
  fail "root must only activate the built store path"
[[ $(cat "$scratch/state/deployed-commit") == "$first" ]] || fail "the deployed commit must be recorded"
expect "System update complete: testhost runs ${first:0:12}."
expect_clean
[[ -f $checkout/notes.txt ]] || fail "untracked files stay"

# Two new commits: the list shows them and the lock commit, before the build.
printf '{ printer = true; }\n' > "$checkout/flake.nix"
git_c commit -qam "Add the printer"
printf '{ printer = true; power = 1; }\n' > "$checkout/flake.nix"
git_c commit -qam "Tune power"
run_update "$scratch/etc-nixos"
expect_success
second=$(head_rev)
expect "Commits since the deployed generation (${first:0:12}, recorded by the running system): 3"
expect "Add the printer"
expect "Tune power"
grep -Fq "git+file://$checkout?rev=$second#" "$FAKE_LOG" || fail "the build must use the new lock commit"

# A failed build or switch undoes the lock commit; nothing else changes.
for failure in FAKE_BUILD FAKE_SWITCH; do
  before=$(head_rev)
  if [[ $failure == FAKE_BUILD ]]; then
    FAKE_BUILD=fail run_update "$scratch/etc-nixos"
    expect "The build failed; nothing was activated."
  else
    FAKE_SWITCH=fail run_update "$scratch/etc-nixos"
    expect "Activation failed"
  fi
  [[ $status != 0 ]] || fail "$failure must fail the update"
  expect "was undone"
  [[ $(head_rev) == "$before" ]] || fail "$failure must undo the lock commit"
  expect_clean
done
[[ $(cat "$scratch/state/deployed-commit") == "$second" ]] || fail "a failed update must not record a deploy"

# A switch that installed the generation but reported errors keeps the commit.
FAKE_SWITCH=partial run_update "$scratch/etc-nixos"
[[ $status != 0 ]] || fail "a partial switch must report failure"
third=$(head_rev)
expect "installed and is the boot default"
[[ $third != "$second" ]] || fail "a partial switch keeps the lock commit"
[[ $(cat "$scratch/state/deployed-commit") == "$third" ]] || fail "a partial switch is recorded"

# Without a revision in the running system, this script's record is used.
ln -sfn "$scratch/unrecorded" "$FAKE_CURRENT"
FAKE_UPDATE=none run_update "$scratch/etc-nixos"
expect_success
expect "The inputs were already current; flake.lock is unchanged."
expect "That is the deployed commit (recorded by the last Update All); rebuilding it."
[[ $(head_rev) == "$third" ]] || fail "an unchanged lock file adds no commit"

echo "system-update: ok"
