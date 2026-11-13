# netconsole over the USB tether: kernel messages go to bonhart (usb0 10.55.0.2:6665 → 10.55.0.1:6666,
# UDP) so that a restart that ends unclean after journald has stopped (2026-11-12 23:00: gen 11's
# restart, then iBoot's boot-error fallback) leaves its last lines somewhere. While the system runs,
# the console level stays as booted (loglevel=4: warnings, oopses and panics go out, and the tty stays
# quiet). From the start of shutdown on, everything goes out, including PID 1's and
# systemd-shutdown's own lines once journald is gone.
#
# bonhart listens with m5max-linux tools/netconsole-listen.py. bonhart's firewall trusts only ts0,
# and its config stays as it is: the listener sends a keepalive from bonhart's 6666 to the Mac's
# 6665, and netconsole's packets then pass as replies. The remote MAC is netconsole's default
# (broadcast): the tether's host MAC is not fixed, and no MAC goes into this repo.
#
# Off by default (2026-11-13, prepared at night, untested): netpoll through the USB gadget driver
# hasn't run on this machine, and a deadlock there would hang the Mac. First run attended:
# ackerman.netconsole.enable = true, a switch, the listener on bonhart, `echo t > /proc/sysrq-trigger`
# (a burst of output), then a clean reboot read on bonhart.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.ackerman.netconsole;
  setup = pkgs.writeShellScript "ackerman-netconsole-setup" ''
    set -eu
    T=/sys/kernel/config/netconsole/bonhart
    [ -d $T ] || mkdir $T
    # A live target's parameters can't change: a restart of this unit leaves it as it is
    if [ "$(cat $T/enabled)" = 1 ]; then echo "netconsole: already on"; exit 0; fi
    echo usb0 > $T/dev_name
    echo 10.55.0.2 > $T/local_ip
    echo 6665 > $T/local_port
    echo 10.55.0.1 > $T/remote_ip
    echo 6666 > $T/remote_port
    echo 1 > $T/enabled
    echo "netconsole: on, usb0 10.55.0.2:6665 -> 10.55.0.1:6666"
  '';
in
{
  options.ackerman.netconsole.enable = lib.mkEnableOption "netconsole to bonhart over the USB tether";

  config = lib.mkIf cfg.enable {
    systemd.services.ackerman-netconsole = {
      description = "netconsole to bonhart over the USB tether";
      wantedBy = [ "multi-user.target" ];
      # usb0 has its address from the initrd on (hardware.nix); networkd keeps it
      after = [
        "systemd-networkd.service"
        "sys-kernel-config.mount"
      ];
      restartIfChanged = false;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = setup;
        # Stopped at the start of shutdown: from then on every kernel message goes out
        ExecStop = "${pkgs.util-linux}/bin/dmesg --console-level 8";
      };
    };
  };
}
