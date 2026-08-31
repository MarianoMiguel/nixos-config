{ pkgs, ... }:

{
  # The MT7925 radio does not re-initialise when the kernel restores a
  # hibernation image onto cold hardware: WiFi comes back dead after a
  # hibernate/resume cycle. Reload the in-tree driver on resume to force a
  # fresh PCI probe; NetworkManager then reconnects on the reappearing device.
  # post-resume.target is reached after suspend and hibernate alike, so this
  # also covers the suspend-then-hibernate fallback if it is ever re-enabled.
  powerManagement.resumeCommands = ''
    ${pkgs.kmod}/bin/modprobe -r mt7925e || true
    ${pkgs.kmod}/bin/modprobe mt7925e || true
  '';

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

  # This hardware exposes only s2idle, and s2idle repeatedly enters sleep but
  # wedges the amdgpu / Strix Point resume path: the machine reaches a
  # blinking-light low-power state that nothing wakes. Trusting s2idle on
  # linuxPackages_latest (commit 028a923) regressed exactly this way, so fail
  # closed again: disable suspend entirely and hibernate to the dedicated
  # encrypted swap partition instead, which resumes reliably from a cold
  # power-on. Do NOT re-enable AllowSuspend without confirming resume works.
  systemd.sleep.settings.Sleep = {
    AllowSuspend = false;
    AllowSuspendThenHibernate = false;
    AllowHibernation = true;
  };

  # In a GNOME session gnome-settings-daemon, not logind, owns the power key
  # and idle policy, so the logind rules above do not apply there. Mirror the
  # hibernate-only policy: replayed power-key events must not act, a closed lid
  # hibernates on either power source, and idle hibernates only on battery so
  # long plugged-in builds are never interrupted.
  home-manager.users.mariano.dconf.settings."org/gnome/settings-daemon/plugins/power" = {
    power-button-action = "nothing";
    lid-close-ac-action = "hibernate";
    lid-close-battery-action = "hibernate";
    sleep-inactive-ac-type = "nothing";
    sleep-inactive-battery-type = "hibernate";
  };
}
