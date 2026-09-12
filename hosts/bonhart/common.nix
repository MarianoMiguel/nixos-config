{
  config,
  lib,
  pkgs,
  ...
}:

let
  brotherHL1210W = pkgs.callPackage ../../packages/cups-brother-hl1210w.nix {
    inherit pkgs;
  };
  setPowerProfileForPowerSource = pkgs.writeShellScript "set-power-profile-for-power-source" ''
    profile=balanced
    if [ -r /sys/class/power_supply/AC/online ] \
      && [ "$(${pkgs.coreutils}/bin/cat /sys/class/power_supply/AC/online)" = 1 ]; then
      profile=performance
    fi

    exec ${pkgs.power-profiles-daemon}/bin/powerprofilesctl set "$profile"
  '';
in
{
  imports = [
    ../nixos-dev/hardware-common.nix
    ../../profiles/workstation.nix
    ../../modules/nixos/displaylink.nix
    ../../modules/nixos/fingerprint.nix
    ../../modules/nixos/local-web-hosting.nix
    ../../modules/nixos/intervals.nix
    ../../modules/nixos/overfly.nix
    ../../modules/nixos/power.nix
    ../../modules/nixos/battery.nix
    ../../modules/nixos/tv-remotes.nix
  ]
  ++ lib.optional (builtins.pathExists ./local.nix) ./local.nix;

  networking.hostName = "bonhart";

  # The Elgato Prompter teleprompter is a DisplayLink device (USB 17e9:ff1a),
  # so it only comes up as a display with the EULA-gated DisplayLink stack
  # (evdi + the proprietary DisplayLinkManager). Enable it here as a tracked
  # setting: a flake checkout outside /etc/nixos cannot see the gitignored
  # storage.nix, so the choice must live in a committed file.
  mariano.displaylink.enable = true;

  services.localWebHosting = {
    enable = true;
    hostName = "bonhart.local";
    title = "Bonhart Local";
    tls.enable = true;
    # Tailscale-only services stay Tailscale-only. The gateway adds no
    # authentication to a dedicated-port application, so proxying one onto
    # the Wi-Fi address would hand it to every device on the LAN.
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # Keep the multi-boot menu available without adding the default five-second
  # pause to every normal startup.
  boot.loader.timeout = 2;
  # Stay on the newest maintained LTS series. Strix Point still receives the
  # current amdgpu and s2idle fixes, while DisplayLink's EVDI module cannot yet
  # compile against the short-lived 7.2 kernel selected by linuxPackages_latest.
  boot.kernelPackages = pkgs.linuxPackages_6_18;
  boot.extraModprobeConfig = ''
    options cfg80211 ieee80211_regdom=AR
    options mt7925e disable_aspm=Y
  '';
  # The Radeon 890M display microcontroller can wedge in the DCN 3.5 idle
  # power / panel self-refresh workers, including during s2idle resume.  The
  # resulting amdgpu soft lockup freezes the display and remote access.
  #
  # 0x800 = DC_DISABLE_IPS, 0x10 = DC_DISABLE_PSR.
  boot.kernelParams = [ "amdgpu.dcdebugmask=0x810" ];

  # Keep the MT7925 on conservative runtime settings. The Wi-Fi driver is the
  # kernel's own mt7925e: the out-of-tree patch set this used to carry stopped
  # compiling once the ieee80211_mgmt layout changed, and upstream has not
  # tracked a kernel this new. The modprobe options above apply to the in-tree
  # module unchanged.
  networking.networkmanager.wifi.powersave = false;
  hardware.enableRedistributableFirmware = true;

  # Use the full CPU profile on AC and a still-responsive balanced profile on
  # battery; plugging or unplugging the adapter reapplies the policy.
  systemd.services.power-profile-auto = {
    description = "Select a responsive power profile for the current power source";
    wantedBy = [ "graphical.target" ];
    wants = [ "power-profiles-daemon.service" ];
    after = [ "power-profiles-daemon.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = setPowerProfileForPowerSource;
    };
  };
  services.udev.extraRules = ''
    SUBSYSTEM=="power_supply", KERNEL=="AC", ACTION=="change", TAG+="systemd", ENV{SYSTEMD_WANTS}+="power-profile-auto.service"
  '';

  # No hardware watchdog and no panic-on-lockup, on purpose. Hibernation
  # freezes userspace, systemd included, before the kernel writes the memory
  # image to the encrypted swap. The watchdog core keeps the SP5100 timer
  # armed to fire RuntimeWatchdogSec after systemd's last ping, the sp5100_tco
  # driver has no sleep handling, and systemd-sleep never touches the
  # watchdog, so a 60 s watchdog reset the laptop whenever the image took
  # longer than a minute to write. It came back up at the LUKS prompt with the
  # backlight on and drained the battery inside the closed lid. The
  # softlockup/hardlockup panic sysctls with kernel.panic=30 end the same way.
  # Both were agent-host conveniences; on a laptop a hard freeze is a
  # ten-second hold of the power button.

  time.timeZone = "America/Argentina/Buenos_Aires";

  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "es_AR.UTF-8";
    LC_IDENTIFICATION = "es_AR.UTF-8";
    LC_MEASUREMENT = "es_AR.UTF-8";
    LC_MONETARY = "es_AR.UTF-8";
    LC_NAME = "es_AR.UTF-8";
    LC_NUMERIC = "es_AR.UTF-8";
    LC_PAPER = "es_AR.UTF-8";
    LC_TELEPHONE = "es_AR.UTF-8";
    LC_TIME = "es_AR.UTF-8";
  };

  services.printing = {
    enable = true;
    drivers = with pkgs; [
      brlaser
      brotherHL1210W
    ];
  };

  system.stateVersion = "25.11";

}
