#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
scratch=$(mktemp -d)
fake_bin="$scratch/bin"
home="$scratch/home"
outside="$scratch/outside"
user=$(id -un)
key='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFirstTestKey agent@test'
second_key='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAISecondTestKey phone@test'

cleanup() {
  rm -rf "$scratch"
}
trap cleanup EXIT

mkdir -p "$fake_bin" "$home" "$outside"

# The target account is the one running the test, with its home in scratch.
cat > "$fake_bin/getent" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ ${1:-} == passwd && ${2:-} == "$TEST_USER" ]] || exit 2
printf '%s:x:%s:%s::%s:/bin/sh\n' "$TEST_USER" "$(id -u)" "$(id -g)" "$TEST_HOME"
EOF

cat > "$fake_bin/ssh-keygen" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ ${1:-} == -l && ${2:-} == -f ]] || exit 1
grep -q '^ssh-ed25519 AAAA' "$3"
printf '%s\n' '256 SHA256:test agent@test (ED25519)'
EOF

cat > "$fake_bin/systemctl" <<'EOF'
#!/usr/bin/env bash
exit 3
EOF
chmod +x "$fake_bin/getent" "$fake_bin/ssh-keygen" "$fake_bin/systemctl"

printf '%s\n' "$key" > "$scratch/agent.pub"

run_authorize() {
  env \
    PATH="$fake_bin:$PATH" \
    TEST_USER="$user" \
    TEST_HOME="$home" \
    SSH_TARGET_USER="$user" \
    timeout 20 "$repo/scripts/authorize-agent-ssh-key.sh" "$@"
}

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

expect_refusal() {
  local expected=$1 output status=0
  shift
  output=$(run_authorize "$@" 2>&1 </dev/null) || status=$?
  (( status != 0 && status != 124 )) \
    || fail "Expected a refusal ($expected), got exit $status: $output"
  grep -Fq -- "$expected" <<< "$output" \
    || fail "Expected \"$expected\" in: $output"
}

# A fresh account gets ~/.ssh (700) and authorized_keys (600) with the key.
output=$(run_authorize "$scratch/agent.pub" 2>&1)
grep -Fq "Authorized key for $user:" <<< "$output"
[[ $(stat -c %a "$home/.ssh") == 700 ]]
[[ $(stat -c %a "$home/.ssh/authorized_keys") == 600 ]]
[[ $(cat "$home/.ssh/authorized_keys") == "$key" ]]

# Running it again changes nothing; a pasted key is appended.
output=$(run_authorize "$scratch/agent.pub" 2>&1)
grep -Fq "Key is already authorized for $user." <<< "$output"
printf '%s\n' "$second_key" | run_authorize >/dev/null 2>&1
[[ $(cat "$home/.ssh/authorized_keys") == "$key"$'\n'"$second_key" ]]

# A planted authorized_keys symlink is refused and its target left alone,
# whether the target exists or not.
rm "$home/.ssh/authorized_keys"
printf '%s\n' 'not yours' > "$outside/victim"
chmod 644 "$outside/victim"
ln -s "$outside/victim" "$home/.ssh/authorized_keys"
expect_refusal 'it is a symbolic link' "$scratch/agent.pub"
[[ $(cat "$outside/victim") == 'not yours' ]]
[[ $(stat -c %a "$outside/victim") == 644 ]]

rm "$home/.ssh/authorized_keys"
ln -s "$outside/missing" "$home/.ssh/authorized_keys"
expect_refusal 'it is a symbolic link' "$scratch/agent.pub"
[[ ! -e $outside/missing ]]

# A FIFO in its place is refused instead of blocking the script.
rm "$home/.ssh/authorized_keys"
mkfifo "$home/.ssh/authorized_keys"
expect_refusal 'it is not a regular file' "$scratch/agent.pub"

# A planted ~/.ssh symlink is refused before anything is created or changed.
rm -rf "$home/.ssh"
mkdir "$outside/ssh"
chmod 755 "$outside/ssh"
ln -s "$outside/ssh" "$home/.ssh"
expect_refusal 'it is a symbolic link' "$scratch/agent.pub"
[[ -z $(ls -A "$outside/ssh") ]]
[[ $(stat -c %a "$outside/ssh") == 755 ]]

# The key file itself must be a regular file, not a link or a FIFO.
rm "$home/.ssh"
ln -s "$scratch/agent.pub" "$scratch/link.pub"
expect_refusal 'it is a symbolic link' "$scratch/link.pub"
mkfifo "$scratch/agent.fifo"
expect_refusal 'it is not a regular file' "$scratch/agent.fifo"
[[ ! -e $home/.ssh ]]

printf 'Agent SSH key authorization tests passed.\n'
