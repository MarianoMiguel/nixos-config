#!/usr/bin/env bash
# Run on Mariano's Apple Silicon Mac; no administrator privileges required.
set -euo pipefail
umask 077
source_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
target_dir="$HOME/Library/Application Support/Bonhart/fido-bridge"
mkdir -p "$target_dir"
chmod 700 "$target_dir"
if [[ ! -x "$target_dir/.venv/bin/python" ]]; then
  /opt/homebrew/bin/uv venv --python /opt/homebrew/bin/python3.14 "$target_dir/.venv"
fi
/opt/homebrew/bin/uv pip install --require-hashes --only-binary=:all: \
  --python "$target_dir/.venv/bin/python" -r "$source_dir/requirements.lock"
if [[ "$source_dir/bridge.py" != "$target_dir/bridge.py" ]]; then
  install -m600 "$source_dir/bridge.py" "$target_dir/bridge.py"
fi
"$target_dir/.venv/bin/python" "$target_dir/bridge.py" list
printf '%s\n' 'Installed. The helper starts only when Bonhart connects over SSH.'
