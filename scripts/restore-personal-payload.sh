#!/usr/bin/env bash
set -euo pipefail

payload=${1:?Usage: restore-personal-payload.sh PAYLOAD.tar.zst [target-home]}
target_home=${2:-/home/mariano}
owner=${OWNER:-}

if [[ ! -f "$payload" ]]; then
  echo "Payload does not exist: $payload" >&2
  exit 1
fi

mkdir -p "$target_home"

tar \
  --extract \
  --file "$payload" \
  --xattrs \
  --acls \
  --preserve-permissions \
  --directory "$target_home"

if [[ -z "$owner" ]]; then
  if id mariano >/dev/null 2>&1; then
    owner="mariano:users"
  else
    owner="1000:100"
  fi
fi

for path in \
  Development \
  .ssh \
  .gitconfig \
  .nvm \
  .npm \
  .config/gh \
  .config/git \
  .config/Code/User/globalStorage \
  .config/Slack \
  .config/slack \
  .config/Codex \
  .codex \
  .claude
do
  if [[ -e "$target_home/$path" ]]; then
    chown -R "$owner" "$target_home/$path"
  fi
done

if [[ -d "$target_home/.ssh" ]]; then
  chmod 700 "$target_home/.ssh"
  find "$target_home/.ssh" -type f -name 'id_*' ! -name '*.pub' -exec chmod 600 {} +
  find "$target_home/.ssh" -type f \( -name '*.pub' -o -name 'known_hosts*' -o -name 'config' \) -exec chmod 644 {} +
fi

echo "Restored payload into $target_home"
