#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Authorize an agent machine's SSH public key for mariano on this machine.

Usage:
  authorize-agent-ssh-key.sh [PUBLIC_KEY_FILE]

If PUBLIC_KEY_FILE is omitted, the script prompts you to paste one public-key
line. Generate the key on the agent machine and provide only its .pub file or
the line printed from it. Never copy the private key to this machine.

Under sudo the key is written as the target account, and the script refuses a
symbolic link or non-regular file in place of the key file, ~/.ssh or
~/.ssh/authorized_keys.

Environment:
  SSH_TARGET_USER  Account to authorize (default: mariano)
USAGE
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" ]]; then
  usage
  exit 0
fi

if (( $# > 1 )); then
  usage >&2
  exit 2
fi

target_user=${SSH_TARGET_USER:-mariano}
passwd_entry=$(getent passwd "$target_user" || true)

if [[ -z $passwd_entry ]]; then
  echo "User does not exist: $target_user" >&2
  exit 1
fi

target_home=$(cut -d: -f6 <<<"$passwd_entry")
target_uid=$(id -u "$target_user")
target_gid=$(id -g "$target_user")
current_user=$(id -un)

if (( EUID != 0 )) && [[ $current_user != "$target_user" ]]; then
  echo "Run this as $target_user, or use sudo." >&2
  exit 1
fi

# Everything that touches the target's ~/.ssh runs as the target account, so
# under sudo a symbolic link planted there reaches only files that account
# could already write, never root's.
as_target() {
  if (( EUID == 0 )) && [[ $current_user != "$target_user" ]]; then
    setpriv --reuid="$target_uid" --regid="$target_gid" --init-groups -- "$@"
  else
    "$@"
  fi
}

# On top of that, refuse symbolic links and anything that is not the expected
# kind (a FIFO or device where a file should be), and open files with
# O_NOFOLLOW.
refuse() {
  echo "Refusing $1: $2." >&2
  exit 1
}

require_kind() {
  local kind=$1 path=$2
  if [[ -L $path ]]; then
    refuse "$path" "it is a symbolic link"
  fi
  if [[ -e $path ]]; then
    case $kind in
      directory) [[ -d $path ]] || refuse "$path" "it is not a directory" ;;
      file) [[ -f $path ]] || refuse "$path" "it is not a regular file" ;;
    esac
  fi
}

require_owned_by_target() {
  if [[ -e $1 && $(stat -c %u -- "$1") != "$target_uid" ]]; then
    refuse "$1" "it is not owned by $target_user"
  fi
}

append_nofollow() {
  as_target dd of="$1" oflag=append,nofollow conv=notrunc status=none
}

if (( $# == 1 )); then
  public_key_file=$1
  require_kind file "$public_key_file"
  if [[ ! -f $public_key_file ]]; then
    echo "Public key file not found: $public_key_file" >&2
    exit 1
  fi
  public_key=$(dd if="$public_key_file" iflag=nofollow status=none)
else
  echo "Paste the agent machine's SSH public key, then press Enter:"
  IFS= read -r public_key
fi

public_key=${public_key%$'\r'}

if [[ -z $public_key || $public_key == *$'\n'* ]]; then
  echo "Expected exactly one non-empty public-key line." >&2
  exit 1
fi

case $public_key in
  ssh-ed25519\ * | sk-ssh-ed25519@openssh.com\ *) ;;
  *)
    echo "Expected an Ed25519 SSH public key (ssh-ed25519 or sk-ssh-ed25519)." >&2
    exit 1
    ;;
esac

temporary_directory=$(mktemp -d)
trap 'rm -rf -- "$temporary_directory"' EXIT
printf '%s\n' "$public_key" >"$temporary_directory/key.pub"

if ! ssh-keygen -l -f "$temporary_directory/key.pub" >/dev/null; then
  echo "The supplied public key is not valid." >&2
  exit 1
fi

ssh_directory="$target_home/.ssh"
authorized_keys="$ssh_directory/authorized_keys"

require_kind directory "$ssh_directory"
require_owned_by_target "$ssh_directory"
as_target install -d -m 700 "$ssh_directory"
require_kind file "$authorized_keys"
require_owned_by_target "$authorized_keys"
# Creates the file if it is missing, like touch, but without following links.
append_nofollow "$authorized_keys" </dev/null
as_target chmod 600 "$authorized_keys"

if as_target grep -qxF -- "$public_key" "$authorized_keys"; then
  echo "Key is already authorized for $target_user."
else
  printf '%s\n' "$public_key" | append_nofollow "$authorized_keys"
  echo "Authorized key for $target_user:"
  ssh-keygen -l -f "$temporary_directory/key.pub"
fi

if systemctl is-active --quiet sshd.service; then
  echo "sshd.service is running. From the agent machine, test with:"
else
  echo "Warning: sshd.service is not running yet. Activate the NixOS configuration first." >&2
  echo "After SSH is running, test from the agent machine with:"
fi

echo "  ssh -o BatchMode=yes $target_user@nixos-dev 'hostname'"
