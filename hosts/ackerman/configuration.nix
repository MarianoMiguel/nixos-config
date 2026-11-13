# ackerman: Mariano's MacBook Pro 16-inch M5 Max (J716C, Mac17,6, T6050), named the way bonhart
# is bonhart. The Linux bring-up lives in MarianoMiguel/m5max-linux; this host is its NixOS side:
# LUKS2 + btrfs, booted by m1n1 payloads (no UEFI), niri on the GPU. Everything per unit (the
# kernel with this unit's GPU voltages, m1n1, Apple firmware) comes from the private input
# ackerman-private; none of it is in this repository.
{ lib, pkgs, ... }:

let
  keys = import ./files/keys/authorized-keys.nix;
in
{
  imports = [
    ./hardware.nix
    ./boot-m1n1.nix
    # The boot menu's systemd-boot entries for boot.bin.uboot (off unless ackerman.uboot.enable)
    ./uboot.nix
    # The bundle: the bundle stage-2, the DCP hand-off on, the boot menu's entries
    ./bundle.nix
    ./disk.nix
    ./network.nix
    # Kernel messages to bonhart over the tether (off unless ackerman.netconsole.enable)
    ./netconsole.nix
    ./desktop.nix
    ./session.nix
    ./comfort.nix
    ./audio.nix
    ./thermal.nix
    ./apps-extra.nix
    ./parity.nix
    ./tailscale.nix
    # x86_64 programs through FEX in 4K-page trees (route B; ackerman.x86.enable)
    ./x86.nix
    # bonhart's apps from their vendors' arm64 builds, and LibrePods
    ./apps-arm64.nix
    # Hardware video decoding (the AVD): firmware, the VA-API driver, vainfo
    ./avd.nix
    ../../modules/nixos/nix.nix
    # Mariano's apps, as on his other machines. The desktop is stock niri + stock DMS (session.nix,
    # 2026-11-09), not his niri + Folio desktop (niri-folio.nix). Not here:
    # GNOME and its login screen (gnome.nix, login-screen.nix, desktop.nix, vicinae.nix, voice.nix),
    # networking.nix (network.nix has NetworkManager on iwd; tailscale.nix has Tailscale and Rex;
    # parity.nix Proton VPN, Avahi and printing; OpenSnitch is Mariano's call),
    # users.nix (root has no
    # password here), Update All (system-actions.nix), and bonhart's hardware and services.
    ../../modules/nixos/apps.nix
    ../../modules/nixos/backups.nix
    ../../modules/nixos/development.nix
    ../../modules/nixos/fonts.nix
    ../../modules/nixos/home.nix
    ../../modules/nixos/manifesto.nix
    ../../modules/nixos/neovim.nix
    ../../modules/nixos/reminders.nix
    ../../modules/nixos/themeport.nix
    ../../modules/nixos/tmux.nix
    ../../modules/nixos/virtualisation.nix
  ];

  networking.hostName = "ackerman";
  time.timeZone = "America/Argentina/Buenos_Aires";
  i18n.defaultLocale = "en_US.UTF-8";

  # As on the Arch daily: mariano (uid 1001, so /home from Arch keeps its owner) administers with
  # his own password; root has none (SSH keys only). The password hash comes over from Arch at
  # install time and stays on the Mac.
  users.mutableUsers = true;
  users.users.root.hashedPassword = "!";
  users.users.mariano = {
    isNormalUser = true;
    uid = 1001;
    description = "Mariano";
    extraGroups = [
      "wheel"
      "video"
      "render"
      "input"
      "audio"
      # ydotool types for the apps that need it (apps.nix enables the daemon)
      "ydotool"
      # Wi-Fi from DMS's network panel (NetworkManager) without a password prompt
      "networkmanager"
    ];
    openssh.authorizedKeys.keys = keys.macbook;
    # His shell, as home.nix configures it (zsh, oh-my-zsh, atuin). sudo keeps asking for his
    # own password: users.nix's `Defaults rootpw` is for the machines with an administrator one.
    shell = pkgs.zsh;
  };
  programs.zsh.enable = true;

  # apps.nix, for the bring-up kernel and aarch64: OBS's virtual camera is an out-of-tree module
  # (v4l2loopback) this kernel is not built with, and Steam is x86 only.
  programs.obs-studio.enableVirtualCamera = lib.mkForce false;
  programs.steam.enable = lib.mkForce false;

  # The YubiKey (works in host mode on either port)
  services.pcscd.enable = true;
  services.udev.packages = with pkgs; [
    libfido2
    yubikey-personalization
  ];

  services.logind.settings.Login.HandleSuspendKey = "ignore";

  environment.systemPackages = with pkgs; [
    btop
    btrfs-progs
    cryptsetup
    curl
    dtc
    fastfetch
    fd
    file
    git
    htop
    iw
    jq
    lm_sensors
    neovim
    pciutils
    python3
    ripgrep
    tmux
    usbutils
    v4l-utils
    wget
    yubikey-manager
    pcsc-tools
  ];

  system.stateVersion = "26.05";
}
