#!/usr/bin/env bash
set -euo pipefail
umask 077

normalize_result() {
  jq -cer '
    if type != "array" or length == 0 or (.[0] | type) != "object" then
      error("LibreSpeed returned no result")
    else
      .[0]
      | {
          version: 1,
          downloadMbps: (.download | tonumber?),
          uploadMbps: (.upload | tonumber?),
          pingMs: (.ping | tonumber?),
          jitterMs: (.jitter | tonumber?),
          server: ((.server.name // "LibreSpeed") | tostring | gsub("[[:cntrl:]<>]"; "") | .[0:120]),
          testedAt: (if (.timestamp | type) == "string" then .timestamp[0:64] else (now | todateiso8601) end)
        }
      | select(
          (.downloadMbps | type) == "number"
          and (.uploadMbps | type) == "number"
          and (.pingMs | type) == "number"
          and (.jitterMs | type) == "number"
          and .downloadMbps >= 0 and .downloadMbps <= 1000000
          and .uploadMbps >= 0 and .uploadMbps <= 1000000
          and .pingMs >= 0 and .pingMs <= 60000
          and .jitterMs >= 0 and .jitterMs <= 60000
        )
    end
  '
}

job_dir=
result_pipe=
result_file=
speed_pid=
normalize_pid=

cleanup_job() {
  if [[ -n ${result_pipe:-} && -p $result_pipe ]]; then
    rm -f -- "$result_pipe"
  fi
  if [[ -n ${result_file:-} && -f $result_file ]]; then
    rm -f -- "$result_file"
  fi
  if [[ -n ${job_dir:-} && -d $job_dir ]]; then
    rmdir -- "$job_dir" 2>/dev/null || true
  fi
}

terminate_test() {
  trap - TERM INT HUP
  if [[ -n ${speed_pid:-} ]] && kill -0 "$speed_pid" 2>/dev/null; then
    kill -TERM -- "-$speed_pid" 2>/dev/null || kill -TERM "$speed_pid" 2>/dev/null || true
  fi
  if [[ -n ${normalize_pid:-} ]] && kill -0 "$normalize_pid" 2>/dev/null; then
    kill -TERM "$normalize_pid" 2>/dev/null || true
  fi
  [[ -z ${speed_pid:-} ]] || wait "$speed_pid" 2>/dev/null || true
  [[ -z ${normalize_pid:-} ]] || wait "$normalize_pid" 2>/dev/null || true
  exit 143
}

case ${1:-run} in
  run)
    runtime_dir=${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}
    lock_file="$runtime_dir/mariano-network-speedtest-${UID}.lock"
    exec 9> "$lock_file"
    if ! flock -n 9; then
      printf 'A network speed test is already running.\n' >&2
      exit 1
    fi
    job_dir=$(mktemp -d "$runtime_dir/mariano-network-speedtest.XXXXXX")
    result_pipe="$job_dir/result"
    result_file="$job_dir/result.json"
    mkfifo -m 600 "$result_pipe"
    trap cleanup_job EXIT
    trap terminate_test TERM INT HUP
    # LibreSpeed only enables its telemetry path when --share or a telemetry
    # flag is present. Keep the invocation explicit, encrypted, and bounded.
    # A complete run includes server discovery, latency sampling, and separate
    # upload/download windows. The previous 35-second ceiling was too close to
    # the normal runtime on higher-latency servers and produced false failures.
    setsid timeout --signal=TERM 60s \
      librespeed-cli --json --secure --ipv4 --duration 8 --timeout 10 > "$result_pipe" &
    speed_pid=$!
    normalize_result < "$result_pipe" > "$result_file" &
    normalize_pid=$!
    normalize_status=0
    speed_status=0
    wait "$speed_pid" || speed_status=$?
    speed_pid=
    wait "$normalize_pid" || normalize_status=$?
    normalize_pid=
    if ((speed_status != 0)); then
      if ((speed_status == 124)); then
        printf 'The speed test timed out after 60 seconds.\n' >&2
      fi
      exit "$speed_status"
    fi
    cat -- "$result_file"
    exit "$normalize_status"
    ;;
  normalize)
    normalize_result
    ;;
  *)
    printf 'usage: mariano-network-speedtest [run|normalize]\n' >&2
    exit 2
    ;;
esac
