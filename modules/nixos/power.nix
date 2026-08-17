{ ... }:

{
  services.logind.settings.Login = {
    # Some ThinkPad wake paths replay the wake event as a short power-key press
    # after resume. Let lid close drive hibernation; ignore software power-key
    # actions so bogus resume events cannot immediately hibernate or power off.
    HandlePowerKey = "ignore";
    HandlePowerKeyLongPress = "ignore";
    HandleSuspendKey = "hibernate";

    HandleLidSwitch = "hibernate";
    HandleLidSwitchExternalPower = "hibernate";
    HandleLidSwitchDocked = "ignore";
    HoldoffTimeoutSec = "30s";
  };

  # This hardware exposes only s2idle, which has repeatedly entered sleep but
  # failed to reach a usable low-power state or resume. Fail closed: use the
  # dedicated encrypted swap partition for hibernation instead.
  systemd.sleep.settings.Sleep = {
    AllowSuspend = false;
    AllowHibernation = true;
  };
}
