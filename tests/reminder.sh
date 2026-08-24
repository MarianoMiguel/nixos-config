#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
scratch=$(mktemp -d)
fake_bin="$scratch/bin"
state_dir="$scratch/state"

cleanup() {
  rm -rf "$scratch"
}
trap cleanup EXIT

mkdir -p "$fake_bin"
cat > "$fake_bin/date" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  '+%s') printf '%s\n' "${MARIANO_REMINDER_NOW:?}" ;;
  '-d @'*' +%H:%M') printf '%s\n' '09:30' ;;
  *) printf 'unexpected date invocation: %s\n' "$*" >&2; exit 1 ;;
esac
EOF
cat > "$fake_bin/flock" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$fake_bin/date" "$fake_bin/flock"

run_reminder() {
  env \
    PATH="$fake_bin:$PATH" \
    MARIANO_REMINDER_STATE_DIR="$state_dir" \
    MARIANO_REMINDER_DRY_RUN=1 \
    MARIANO_REMINDER_NOW="${MARIANO_REMINDER_NOW:-1000}" \
    "$repo/scripts/reminder.sh" "$@"
}

output=$(run_reminder add 5 "Check the oven")
grep -Fq 'notification: Reminder set | Check the oven · 09:30' <<< "$output"
payload=$(run_reminder json)
jq -e '
  length == 1
  and .[0].created == 1000
  and .[0].due == 1300
  and .[0].message == "Check the oven"
' <<< "$payload" >/dev/null

output=$(MARIANO_REMINDER_NOW=1100 run_reminder list)
grep -Fq 'Check the oven' <<< "$output"
grep -Fq 'in 4m' <<< "$output"

MARIANO_REMINDER_NOW=1299 run_reminder deliver >/dev/null
[[ $(run_reminder json | jq length) == 1 ]]

output=$(MARIANO_REMINDER_NOW=1300 run_reminder deliver)
grep -Fq 'notification: Reminder | Check the oven' <<< "$output"
[[ $(run_reminder json | jq length) == 0 ]]

run_reminder add 15 '--review flags safely' >/dev/null
run_reminder add 30 'Second reminder' >/dev/null
printf '%s\n' '{not-json' > "$state_dir/corrupt.json"
[[ $(run_reminder json | jq length) == 2 ]]
run_reminder clear >/dev/null
[[ $(run_reminder json | jq length) == 0 ]]
[[ ! -e $state_dir/corrupt.json ]]

if run_reminder add 0 impossible > "$scratch/invalid.out" 2>&1; then
  printf 'A zero-minute reminder unexpectedly succeeded.\n' >&2
  exit 1
fi
grep -Fq 'Minutes must be a whole number' "$scratch/invalid.out"

printf 'Reminder behavior passed.\n'
