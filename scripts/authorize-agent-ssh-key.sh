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
target_group=$(id -gn "$target_user")
current_user=$(id -un)

if (( EUID != 0 )) && [[ $current_user != "$target_user" ]]; then
  echo "Run this as $target_user, or use sudo." >&2
  exit 1
fi

if (( $# == 1 )); then
  public_key_file=$1
  if [[ ! -f $public_key_file ]]; then
    echo "Public key file not found: $public_key_file" >&2
    exit 1
  fi
  public_key=$(<"$public_key_file")
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

if (( EUID == 0 )); then
  install -d -m 700 -o "$target_user" -g "$target_group" "$ssh_directory"
  touch "$authorized_keys"
  chown "$target_user:$target_group" "$authorized_keys"
else
  install -d -m 700 "$ssh_directory"
  touch "$authorized_keys"
fi
chmod 600 "$authorized_keys"

if grep -qxF -- "$public_key" "$authorized_keys"; then
  echo "Key is already authorized for $target_user."
else
  printf '%s\n' "$public_key" >>"$authorized_keys"
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
