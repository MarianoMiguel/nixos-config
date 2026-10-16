#!/usr/bin/env bash
set -euo pipefail
unit=remote-yubikey.service
case "${1:-help}" in
  start)
    product="${2:-0407}"
    case "$product" in 0407|0402) ;; *) echo 'Choose 0407 (5C) or 0402 (FIDO key).' >&2; exit 2 ;; esac
    if systemctl --user is-active --quiet "$unit"; then
      echo 'Bridge is already running. Use remote-yubikey status or stop.'
      exit 0
    fi
    systemctl --user reset-failed "$unit" 2>/dev/null || true
    systemd-run --user --unit=remote-yubikey --collect --service-type=exec \
      --property=TimeoutStopSec=10 --property=KillMode=control-group \
      /run/wrappers/bin/pkexec @worker@ frontend --product "$product"
    echo 'Complete the administrator dialog to connect. Then: remote-yubikey status'
    ;;
  stop) systemctl --user stop "$unit"; echo 'Remote YubiKey disconnected.' ;;
  status)
    pid="$(systemctl --user show "$unit" -p MainPID --value 2>/dev/null || true)"
    if [[ "$pid" =~ ^[1-9][0-9]*$ && -r "/proc/$pid/comm" ]] && [[ "$(cat "/proc/$pid/comm")" == pkexec ]]; then
      echo 'Waiting for the administrator authentication dialog on Bonhart.'
    elif grep -qs '^HID_PHYS=bonhart-fido/ssh$' /sys/class/hidraw/hidraw*/device/uevent; then
      echo 'Connected: the remote FIDO key is present on Bonhart.'
    else
      echo 'No remote FIDO key is currently present.'
    fi
    systemctl --user status "$unit" --no-pager || true
    journalctl --user -u "$unit" -I -n 8 --no-pager -o cat
    ;;
  list)
    ssh -T -o BatchMode=yes -o StrictHostKeyChecking=yes -o ForwardAgent=no \
      -o ClearAllForwardings=yes -o ConnectTimeout=10 mariano@100.115.44.59 \
      "'/Users/mariano/Library/Application Support/Bonhart/fido-bridge/.venv/bin/python' '/Users/mariano/Library/Application Support/Bonhart/fido-bridge/bridge.py' list"
    ;;
  *)
    cat <<'HELP'
remote-yubikey start [0407|0402]  Connect one Mac YubiKey to Bonhart (default: 5C).
remote-yubikey stop               Disconnect and remove the virtual key.
remote-yubikey status             Show connection state and recent messages.
remote-yubikey list               List compatible keys currently on the Mac.

Touch the physical key on the Mac when Bonhart's browser requests it.
This forwards FIDO authentication only. The connection is manual and stops
when SSH, the key, or this service disconnects. Run start again to reconnect.
HELP
    ;;
esac
