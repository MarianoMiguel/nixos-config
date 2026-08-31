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
    ../../modules/nixos/android-development.nix
    ../../modules/nixos/displaylink.nix
    ../../modules/nixos/fingerprint.nix
    ../../modules/nixos/local-web-hosting.nix
    ../../modules/nixos/intervals.nix
    ../../modules/nixos/power.nix
    ../../modules/nixos/tv-remotes.nix
  ]
  ++ lib.optional (builtins.pathExists ./local.nix) ./local.nix;

  networking.hostName = "bonhart";

  services.localWebHosting = {
    enable = true;
    hostName = "bonhart.local";
    title = "Bonhart Local";
    tls.enable = true;

    # T3 Code binds only to the Tailscale address. nginx owns the same port on
    # the Wi-Fi address and preserves its root-relative assets and WebSockets.
    portApplications.t3-code = {
      title = "T3 Code";
      description = "Local access to the T3 Code instance running on this machine.";
      port = 3773;
      listenAddresses = [ "192.168.68.58" ];
      upstream = "http://100.87.18.64:3773";
      tls = true;
      webSockets = true;
      extraConfig = "proxy_buffering off;";
    };
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # Keep the multi-boot menu available without adding the default five-second
  # pause to every normal startup.
  boot.loader.timeout = 2;
  # Track the newest stable kernel, matching how Fedora runs this machine.
  # The Strix Point s2idle and amdgpu paths receive fixes in nearly every
  # kernel release, and the sleep failures seen here never reproduced on
  # Fedora's current kernel.
  boot.kernelPackages = pkgs.linuxPackages_latest;
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

  # If a kernel lockup ever freezes the machine, reboot automatically instead
  # of requiring a long power-button hold. The SP5100 hardware watchdog is
  # present on this machine.
  systemd.settings.Manager.RuntimeWatchdogSec = "60s";
  boot.kernel.sysctl = {
    "kernel.softlockup_panic" = 1;
    "kernel.hardlockup_panic" = 1;
    "kernel.panic" = 30;
  };

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

  nixpkgs.config.permittedInsecurePackages = [ "docker-28.5.2" ];
}
