{
  config,
  lib,
  pkgs,
  ...
}:

let
  displaylinkPower = pkgs.writeShellScript "displaylink-power" ''
    set -u

    action="''${1:-}"
    input=/tmp/PmMessagesPort_in
    output=/tmp/PmMessagesPort_out
    bash=${lib.getExe pkgs.bash}
    systemctl=${lib.getExe' pkgs.systemd "systemctl"}
    timeout=${lib.getExe' pkgs.coreutils "timeout"}

    warn() {
      printf 'displaylink-power: %s\n' "$1" >&2
    }

    if ! "$systemctl" is-active --quiet dlm.service; then
      exit 0
    fi

    if [ ! -p "$input" ]; then
      warn "DisplayLinkManager is active but its input pipe is unavailable; skipping $action"
      exit 0
    fi

    write_command() {
      if ! "$timeout" --signal=TERM --kill-after=1s 2s "$bash" -c \
        'printf "%s" "$1" > "$2"' _ "$1" "$input"
      then
        warn "timed out writing $1 to DisplayLinkManager; continuing without it"
        return 1
      fi
    }

    case "$action" in
      suspend)
        if [ ! -p "$output" ]; then
          warn "DisplayLinkManager is active but its output pipe is unavailable; skipping suspend"
          exit 0
        fi

        # The timeout covers opening the FIFO too; shell read timeouts do not.
        "$timeout" --signal=TERM --kill-after=1s 1s "$bash" -c \
          'while IFS= read -r -n 1 -t 0.1 _ < "$1"; do :; done' _ "$output" || true

        if write_command S; then
          if ! "$timeout" --signal=TERM --kill-after=1s 10s "$bash" -c \
            'IFS= read -r -n 1 _ < "$1"' _ "$output"
          then
            warn "DisplayLinkManager did not acknowledge suspend; continuing anyway"
          fi
        fi
        ;;
      resume)
        write_command R || true
        ;;
      *)
        warn "expected suspend or resume, got '$action'"
        exit 2
        ;;
    esac
  '';
in

{
  options.mariano.displaylink.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Enable the EULA-gated DisplayLink driver and power hooks.";
  };

  config = lib.mkIf config.mariano.displaylink.enable {
    # The Elgato Prompter is a DisplayLink device rather than a plain USB-C
    # display, so the kernel cannot drive it on its own. The evdi module exposes
    # it as a virtual DRM output and the proprietary DisplayLinkManager daemon
    # copies frames from that output to the device over USB. GNOME renders the
    # virtual output through the primary GPU without compositor-specific setup.
    #
    # Listing "displaylink" is what activates the upstream NixOS module; the
    # remaining entries restate the default list that this definition would
    # otherwise replace. DisplayLinkManager is socket-free and starts on demand
    # from the udev rule matching the device, so it stays stopped while no
    # DisplayLink hardware is attached.
    services.xserver.videoDrivers = [
      "displaylink"
      "modesetting"
      "fbdev"
    ];

    # The upstream DisplayLink hooks open these named pipes directly. A stale
    # pipe with no DisplayLinkManager reader blocks during open, before the
    # shell's read timeout can take effect, and holds sleep.target indefinitely.
    powerManagement.powerDownCommands = lib.mkForce ''
      ${displaylinkPower} suspend
    '';
    powerManagement.resumeCommands = lib.mkForce ''
      ${displaylinkPower} resume
    '';

    # Bound the whole hook as a final guard against regressions in either the
    # proprietary daemon or the wrapper above.
    systemd.services.sleep-actions.serviceConfig = {
      TimeoutStartSec = "20s";
      TimeoutStopSec = "5s";
    };
  };
}
