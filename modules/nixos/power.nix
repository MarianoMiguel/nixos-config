{ ... }:

{
  services.logind.settings.Login = {
    # Some ThinkPad wake paths replay the wake event as a short power-key press
    # after resume. Let lid close drive sleep; ignore software power-key
    # actions so bogus resume events cannot immediately hibernate or power off.
    HandlePowerKey = "ignore";
    HandlePowerKeyLongPress = "ignore";
    HandleSuspendKey = "suspend-then-hibernate";

    HandleLidSwitch = "suspend-then-hibernate";
    HandleLidSwitchExternalPower = "suspend-then-hibernate";
    HandleLidSwitchDocked = "ignore";
    HoldoffTimeoutSec = "30s";
  };

  # Older kernels repeatedly entered s2idle but failed to reach a usable
  # low-power state or resume, so suspend used to be disabled outright in
  # favor of hibernation. With boot.kernelPackages tracking the newest stable
  # kernel this hardware sleeps the way it does on Fedora, so s2idle is
  # trusted again: suspend-then-hibernate wakes instantly from short lid
  # closes and falls back to the encrypted swap partition after the delay
  # below. If s2idle regresses, set AllowSuspend = false to return to pure
  # hibernation.
  systemd.sleep.settings.Sleep = {
    AllowSuspend = true;
    AllowSuspendThenHibernate = true;
    AllowHibernation = true;
    HibernateDelaySec = "2h";
  };

  # In a GNOME session gnome-settings-daemon, not logind, owns the power key
  # and idle policy, so the logind rules above do not apply there. Mirror
  # them: replayed power-key events must not act, closing the lid sleeps the
  # machine on either power source (GNOME itself keeps it awake while an
  # external display is attached), and idle sleep happens only on battery so
  # long plugged-in builds are never interrupted.
  home-manager.users.mariano.dconf.settings."org/gnome/settings-daemon/plugins/power" = {
    power-button-action = "nothing";
    lid-close-ac-action = "suspend";
    lid-close-battery-action = "suspend";
    sleep-inactive-ac-type = "nothing";
    sleep-inactive-battery-type = "suspend";
  };
}
