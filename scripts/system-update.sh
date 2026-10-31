# shellcheck shell=bash
# Body of mariano-system-update and mariano-system-update-all (the Settings
# app's Update All): update the flake inputs, commit the new flake.lock, build
# that commit and switch to it. Only committed code is ever built.
#
# modules/nixos/system-actions.nix sources this after setting host,
# update_description, commit_summary, update_inputs (an array; empty means
# every input), config_link (/etc/nixos), state_dir, current_system and
# system_profile; tests/system-update.sh sets them to a scratch tree.
#
# It runs as root through sudo. Everything that reads the checkout (git, the
# input update, evaluation and the build) runs as the checkout's owner; root
# only activates the store path that build produced.

set -eu

refuse() {
  printf '%s\n' "$@" >&2
  exit 1
}

# /etc/nixos is a symlink to the administrator's checkout, owned by root or
# the user who ran sudo.
config_dir=$(readlink -f "$config_link")
if [ ! -d "$config_dir" ] || [ ! -f "$config_dir/flake.lock" ]; then
  refuse "$config_link must resolve to a configuration directory with a flake.lock."
fi
owner=$(stat -c %U "$config_dir")
if [ "$owner" != root ] && [ "$owner" != "${SUDO_USER:-}" ]; then
  refuse "Refusing to update: $config_dir is owned by $owner, not root or the invoking user."
fi
# Root activates whatever this checkout describes, so nobody but root and the
# owner may be able to write it, git metadata included. Symlinks are fine:
# root never reads the tree, and a git build only follows links inside it.
# Untracked agent worktrees under .claude/ are never built.
unsafe=$(find "$config_dir" -xdev -path "$config_dir/.claude" -prune -o \( \
  \( ! -user root ! -user "$owner" \) \
  -o \( ! -type l -perm /022 \) \
  \) -print -quit)
if [ -n "$unsafe" ]; then
  refuse "Refusing to update: $config_dir contains a path others can change: $unsafe"
fi

run_as_owner() {
  if [ "$owner" = root ]; then
    "$@"
  else
    owner_home=$(getent passwd "$owner" | cut -d: -f6)
    runuser -u "$owner" -- env HOME="$owner_home" "$@"
  fi
}
git_owner() {
  run_as_owner git -C "$config_dir" "$@"
}

# At most twelve entries of git status, indented.
show_paths() {
  awk 'NR <= 12 { print "  " $0 } END { if (NR > 12) print "  ...and " NR - 12 " more" }'
}

# --- Only committed code -----------------------------------------------------

if [ "$(git_owner rev-parse --show-toplevel 2>/dev/null || true)" != "$config_dir" ]; then
  refuse "Update All builds only committed code, but $config_dir is not a git checkout." \
    "Point $config_link at a clone of the configuration, then run it again."
fi
before=$(git_owner rev-parse --verify --quiet 'HEAD^{commit}') ||
  refuse "Update All builds only committed code, but $config_dir has no commits yet."

status=$(git_owner status --porcelain --untracked-files=all --ignored=matching)
changes=$(printf '%s\n' "$status" | grep -v -e '^?? ' -e '^!! ' -e '^$' || true)
if [ -n "$changes" ]; then
  {
    echo "Update All builds only committed code, and $config_dir has uncommitted changes:"
    printf '%s\n' "$changes" | show_paths
    echo "Commit or stash them, then run Update All again."
  } >&2
  exit 1
fi
# A build from git leaves out every file git does not track, and an optional
# import (builtins.pathExists) would then vanish without an error.
loose=$(printf '%s\n' "$status" | grep -E '^(\?\?|!!) .*\.nix"?$' || true)
if [ -n "$loose" ]; then
  {
    echo "Update All builds only committed code, and these .nix files are not in git, so the build would leave them out:"
    printf '%s\n' "$loose" | sed -e 's/^?? /untracked: /' -e 's/^!! /ignored:   /' | show_paths
    echo "Commit them (a git-ignored one needs a !path exception in .gitignore first, like hosts/bonhart/storage.nix), or move them out of the checkout."
  } >&2
  exit 1
fi

# --- Update the inputs and commit the lock file --------------------------------

lock_commit=
build_dir=
activating=0

restore_lock() {
  git_owner restore --source=HEAD --staged --worktree -- flake.lock 2>/dev/null || true
}
# Put the checkout back as it was before this run: drop the lock file commit
# made here, unless something else has been committed on top of it since.
undo_lock_update() {
  if [ -z "$lock_commit" ]; then
    restore_lock
  elif [ "$(git_owner rev-parse HEAD)" = "$lock_commit" ]; then
    if git_owner reset --quiet --keep "$before"; then
      echo "The flake.lock commit ${lock_commit:0:12} was undone; it stays reachable by that hash." >&2
    fi
  else
    echo "HEAD moved past the flake.lock commit ${lock_commit:0:12}, so it was left in place." >&2
  fi
}
cleanup() {
  if [ -n "$build_dir" ]; then
    run_as_owner rm -rf "$build_dir"
  fi
}
interrupted() {
  if [ "$activating" = 1 ]; then
    echo "Interrupted while activating; the switch carries on in the background." >&2
  else
    undo_lock_update
  fi
  exit 130
}
trap cleanup EXIT
trap interrupted INT TERM HUP

# Nix commits the lock file as the owner; fall back to a local identity where
# git has none, rather than failing after the update.
identity=()
git_owner config user.name >/dev/null || identity+=("GIT_AUTHOR_NAME=$owner" "GIT_COMMITTER_NAME=$owner")
git_owner config user.email >/dev/null || identity+=("GIT_AUTHOR_EMAIL=$owner@$host" "GIT_COMMITTER_EMAIL=$owner@$host")

echo "$update_description"
if ! run_as_owner env "${identity[@]}" nix flake update --flake "git+file://$config_dir" \
  --commit-lock-file --option commit-lock-file-summary "$commit_summary" "${update_inputs[@]}"; then
  restore_lock
  refuse "Input update failed; flake.lock is back at the committed version."
fi
target=$(git_owner rev-parse HEAD)
if [ "$target" != "$before" ]; then
  lock_commit=$target
  echo "Committed the new flake.lock as ${target:0:12}."
else
  echo "The inputs were already current; flake.lock is unchanged."
fi
if ! git_owner diff --quiet HEAD -- flake.lock; then
  undo_lock_update
  refuse "The new flake.lock was not committed; it is back at the committed version."
fi

# --- What changes ----------------------------------------------------------------

# The running generation records its commit (system.configurationRevision, set
# from the flake's self.rev); this script's own record is the fallback.
deployed=$("$current_system/sw/bin/nixos-version" --configuration-revision 2>/dev/null || true)
recorded_by="recorded by the running system"
if [ -z "$deployed" ] && [ -s "$state_dir/deployed-commit" ]; then
  deployed=$(cat "$state_dir/deployed-commit")
  recorded_by="recorded by the last Update All"
fi
dirty=
case $deployed in
  *-dirty)
    deployed=${deployed%-dirty}
    dirty=", built with uncommitted changes"
    ;;
esac

echo
echo "Deploying ${target:0:12} to $host: $(git_owner log -1 --format=%s "$target")"
if [ -z "$deployed" ]; then
  echo "The running system does not record the commit it was built from, so there is no list of new commits. Generations built from now on record theirs."
elif ! git_owner cat-file -e "$deployed^{commit}" 2>/dev/null; then
  echo "The deployed commit ${deployed:0:12} ($recorded_by) is not in this checkout, so the new commits cannot be listed."
elif [ "$deployed" = "$target" ]; then
  echo "That is the deployed commit ($recorded_by$dirty); rebuilding it."
else
  count=$(git_owner rev-list --count "$deployed..$target")
  echo "Commits since the deployed generation (${deployed:0:12}, $recorded_by$dirty): $count"
  git_owner log --no-decorate --format='  %h %s' -n 40 "$deployed..$target"
  if [ "$count" -gt 40 ]; then
    echo "  ...and $((count - 40)) more"
  fi
  dropped=$(git_owner rev-list --count "$target..$deployed")
  if [ "$dropped" -gt 0 ]; then
    echo "Note: $dropped deployed commit(s) are not in this build and will be rolled back."
  fi
fi
echo

# --- Build as the owner, activate as root --------------------------------------

flake_ref="git+file://$config_dir?rev=$target"
build_dir=$(run_as_owner mktemp -d -t mariano-system-update.XXXXXX)
echo "Building $flake_ref#$host..."
if ! run_as_owner nix build --out-link "$build_dir/system" \
  "$flake_ref#nixosConfigurations.$host.config.system.build.toplevel"; then
  undo_lock_update
  refuse "The build failed; nothing was activated."
fi
system=$(readlink -f "$build_dir/system")
if [ ! -x "$system/bin/switch-to-configuration" ]; then
  undo_lock_update
  refuse "The build did not produce a NixOS system ($system); nothing was activated."
fi
built_rev=$("$system/sw/bin/nixos-version" --configuration-revision 2>/dev/null || true)
if [ "$built_rev" != "$target" ]; then
  echo "Warning: the new system records commit '${built_rev:-none}', not ${target:0:12}; $state_dir/deployed-commit will still name ${target:0:12}." >&2
fi

record_deploy() {
  install -d -m 0700 "$state_dir"
  printf '%s\n' "$target" > "$state_dir/deployed-commit"
  printf '%s %s %s %s\n' "$(date --iso-8601=seconds)" "$host" "$target" "$system" >> "$state_dir/history"
}

echo "Activating ${target:0:12}..."
activating=1
if ! nixos-rebuild switch --no-reexec --store-path "$system"; then
  activating=0
  if [ "$(readlink -f "$system_profile" || true)" = "$system" ]; then
    record_deploy
    refuse "The new generation is installed and is the boot default, but activating it reported errors (see above)." \
      "The previous generation stays in the boot menu."
  fi
  undo_lock_update
  refuse "Activation failed; the previous generation is still running and still the boot default."
fi
activating=0
trap - INT TERM HUP
record_deploy

echo
echo "System update complete: $host runs ${target:0:12}."
if [ -n "$lock_commit" ]; then
  echo "The flake.lock commit ${lock_commit:0:12} is local to $config_dir; push it when ready."
fi
