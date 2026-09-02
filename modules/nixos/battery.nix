{ lib, pkgs, ... }:

# Toggleable battery charge threshold for Bonhart's internal battery.
#
# Keeping the battery at ~80% instead of a full 100% charge measurably slows
# lithium-ion wear, which is the right default while docked. But an 80% cap is
# wrong the moment the machine goes mobile, so this has to be a one-click
# toggle rather than a fixed policy. The DMS "battery-limit" plugin pill drives
# it; everything it needs lives here.
#
# Three pieces make the toggle instant and durable:
#   * a `battery-charge-limit` helper that writes the sysfs threshold and
#     records the choice in a state file,
#   * a boot-time oneshot that, as root, hands the `wheel` group write access
#     to the threshold attribute and then re-applies the recorded choice. The
#     write grant is what lets the helper run from the unprivileged DMS process
#     with no pkexec password prompt (DMS's own settings tab prompts every
#     time); re-applying is needed because a cold boot resets
#     `charge_control_end_threshold` back to 100.
#
# The permission grant lives in this service rather than a udev rule on
# purpose: a udev `add` rule only fires for devices that appear after it loads,
# so a `nixos-rebuild switch` that never reboots would leave the always-present
# battery ungranted. A changed service, by contrast, is restarted by the switch
# itself, so the toggle works the moment the rebuild lands.
let
  # The health cap. 80 is the widely cited sweet spot for longevity headroom
  # without giving up too much usable capacity.
  healthLimit = 80;

  stateDir = "/var/lib/battery-charge-limit";
  stateFile = "${stateDir}/limit";

  # One helper for every path: the plugin ("health"/"full"), the boot service
  # ("apply"), and the pill's state read ("read"). It walks BAT* and writes
  # whichever end-threshold attribute the driver exposes, mirroring the probe
  # order DMS itself uses. Writes to sysfs succeed either as root (the boot
  # service) or as a wheel user (the plugin, via the udev rule below).
  batteryChargeLimit = pkgs.writeShellApplication {
    name = "battery-charge-limit";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      state_file=${lib.escapeShellArg stateFile}
      health=${toString healthLimit}

      usage() {
        echo "usage: battery-charge-limit {health|full|80|100|read|apply}" >&2
        exit 2
      }

      read_current() {
        for bat in /sys/class/power_supply/BAT*; do
          for attr in charge_control_end_threshold charge_stop_threshold charge_control_limit_max; do
            if [ -r "$bat/$attr" ]; then
              cat "$bat/$attr"
              return 0
            fi
          done
        done
        echo "unknown"
        return 1
      }

      write_value() {
        value=$1
        wrote=0
        for bat in /sys/class/power_supply/BAT*; do
          if [ -e "$bat/charge_control_end_threshold" ]; then
            echo "$value" > "$bat/charge_control_end_threshold" && wrote=1
          elif [ -e "$bat/charge_stop_threshold" ]; then
            echo "$value" > "$bat/charge_stop_threshold" && wrote=1
          elif [ -e "$bat/charge_control_limit_max" ]; then
            echo "$value" > "$bat/charge_control_limit_max" && wrote=1
          fi
        done
        if [ "$wrote" != 1 ]; then
          echo "battery-charge-limit: no writable charge threshold found" >&2
          return 1
        fi
      }

      # Record the choice so the boot service restores it. Best-effort: a read
      # ("read"/"apply") never needs to persist, and applying the threshold
      # must not fail just because the state file is momentarily unwritable.
      persist() {
        if [ -w "$state_file" ] || { [ ! -e "$state_file" ] && [ -w "$(dirname "$state_file")" ]; }; then
          printf '%s\n' "$1" > "$state_file"
        fi
      }

      case "''${1:-}" in
        read)
          read_current
          ;;
        apply)
          if [ -r "$state_file" ]; then
            value=$(cat "$state_file")
          else
            value=$health
          fi
          write_value "$value"
          ;;
        full | 100)
          write_value 100
          persist 100
          ;;
        health | ${toString healthLimit})
          write_value "$health"
          persist "$health"
          ;;
        *)
          usage
          ;;
      esac
    '';
  };
in
{
  environment.systemPackages = [ batteryChargeLimit ];

  # State lives in a wheel-writable file seeded to the health cap, so a machine
  # that has never been toggled still boots into the longevity-friendly limit.
  systemd.tmpfiles.rules = [
    "d ${stateDir} 0775 root wheel -"
    "f ${stateFile} 0664 root wheel - ${toString healthLimit}"
  ];

  # Two jobs, both as root at boot (and on every switch, since a changed unit
  # is restarted): open the threshold attribute to the wheel group so the
  # unprivileged toggle can write it, then re-apply the recorded choice — a
  # cold boot clears the kernel/EC threshold back to 100. sysfs attribute modes
  # persist until the attribute is recreated, which for the internal battery is
  # effectively never. Resume from hibernate restores systemd state from the
  # image rather than re-running this unit, but Lenovo's EC keeps the threshold
  # across a power cycle, so the boot pass is the only one that has to run.
  systemd.services.battery-charge-limit = {
    description = "Grant and restore the battery charge limit";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-tmpfiles-setup.service" ];
    unitConfig.ConditionPathExists = "/sys/class/power_supply/BAT0/charge_control_end_threshold";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStartPre = [
        "${pkgs.coreutils}/bin/chgrp wheel /sys/class/power_supply/BAT0/charge_control_end_threshold"
        "${pkgs.coreutils}/bin/chmod 0664 /sys/class/power_supply/BAT0/charge_control_end_threshold"
      ];
      ExecStart = "${batteryChargeLimit}/bin/battery-charge-limit apply";
    };
  };
}
