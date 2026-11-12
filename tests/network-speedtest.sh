#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
scratch=$(mktemp -d)
fake_bin="$scratch/bin"
arguments="$scratch/arguments"

cleanup() {
  rm -rf "$scratch"
}
trap cleanup EXIT

mkdir -p "$fake_bin"

cat > "$fake_bin/timeout" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[[ $1 == --signal=TERM ]]
[[ $2 == 60s ]]
shift 2
exec "$@"
EOF

cat > "$fake_bin/librespeed-cli" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ ${MARIANO_SPEEDTEST_BLOCK:-0} == 1 ]]; then
  trap 'printf stopped > "${MARIANO_SPEEDTEST_STOPPED:?}"; exit 143' TERM INT HUP
  printf ready > "${MARIANO_SPEEDTEST_READY:?}"
  while :; do
    sleep 1
  done
fi
printf '%s\n' "$@" > "${MARIANO_SPEEDTEST_ARGUMENTS:?}"
printf '%s\n' '[{"timestamp":"2026-08-24T12:34:56Z","server":{"name":"<b>Test Server</b>","url":"https://private.invalid"},"client":{"ip":"203.0.113.7","isp":"Private ISP"},"bytes_sent":123,"bytes_received":456,"ping":12.34,"jitter":1.25,"upload":41.5,"download":382.75,"share":"https://private.invalid/share"}]'
EOF

cat > "$fake_bin/setsid" <<'EOF'
#!/usr/bin/env python3
import os
import sys

os.setsid()
os.execvp(sys.argv[1], sys.argv[1:])
EOF

cat > "$fake_bin/flock" <<'EOF'
#!/usr/bin/env bash
[[ ${MARIANO_FLOCK_FAIL:-0} != 1 ]]
EOF

chmod +x "$fake_bin/timeout" "$fake_bin/librespeed-cli" "$fake_bin/flock" "$fake_bin/setsid"

output=$(env \
  PATH="$fake_bin:$PATH" \
  MARIANO_SPEEDTEST_ARGUMENTS="$arguments" \
  XDG_RUNTIME_DIR="$scratch" \
  bash "$repo/scripts/network-speedtest.sh" run)

jq -e '
  . == {
    version: 1,
    downloadMbps: 382.75,
    uploadMbps: 41.5,
    pingMs: 12.34,
    jitterMs: 1.25,
    server: "bTest Server/b",
    testedAt: "2026-08-24T12:34:56Z"
  }
' <<< "$output" >/dev/null

diff -u <(printf '%s\n' --json --secure --ipv4 --duration 8 --timeout 10) "$arguments"
if grep -Eq -- '--share|--telemetry|--skip-cert-verify' "$arguments"; then
  printf 'The speed test unexpectedly enabled sharing, telemetry, or insecure TLS.\n' >&2
  exit 1
fi

if env \
  PATH="$fake_bin:$PATH" \
  MARIANO_FLOCK_FAIL=1 \
  MARIANO_SPEEDTEST_ARGUMENTS="$arguments" \
  XDG_RUNTIME_DIR="$scratch" \
  bash "$repo/scripts/network-speedtest.sh" run > "$scratch/locked.out" 2>&1; then
  printf 'A concurrent speed test unexpectedly started.\n' >&2
  exit 1
fi
grep -Fq 'already running' "$scratch/locked.out"

ready="$scratch/ready"
stopped="$scratch/stopped"
env \
  PATH="$fake_bin:$PATH" \
  MARIANO_SPEEDTEST_ARGUMENTS="$arguments" \
  MARIANO_SPEEDTEST_BLOCK=1 \
  MARIANO_SPEEDTEST_READY="$ready" \
  MARIANO_SPEEDTEST_STOPPED="$stopped" \
  XDG_RUNTIME_DIR="$scratch" \
  bash "$repo/scripts/network-speedtest.sh" run > "$scratch/cancel.out" 2>&1 &
wrapper_pid=$!
for _ in {1..100}; do
  [[ -e $ready ]] && break
  sleep 0.02
done
[[ -e $ready ]]
kill -TERM "$wrapper_pid"
for _ in {1..100}; do
  ! kill -0 "$wrapper_pid" 2>/dev/null && break
  sleep 0.02
done
if kill -0 "$wrapper_pid" 2>/dev/null; then
  kill -KILL "$wrapper_pid" 2>/dev/null || true
  wait "$wrapper_pid" 2>/dev/null || true
  printf 'Cancelling the speed test left its wrapper running.\n' >&2
  exit 1
fi
wait "$wrapper_pid" 2>/dev/null || true
[[ -e $stopped ]]
shopt -s nullglob
leftover_pipes=("$scratch"/mariano-network-speedtest.*/result)
((${#leftover_pipes[@]} == 0))

for invalid in \
  '[]' \
  '[{"download":"fast","upload":1,"ping":1,"jitter":1}]' \
  '[{"download":1,"upload":1,"ping":70000,"jitter":1}]'; do
  if printf '%s\n' "$invalid" | bash "$repo/scripts/network-speedtest.sh" normalize >/dev/null 2>&1; then
    printf 'An invalid LibreSpeed payload was accepted: %s\n' "$invalid" >&2
    exit 1
  fi
done

printf 'Network speed boundary passed.\n'
