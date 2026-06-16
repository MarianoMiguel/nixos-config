{ lib, ... }:

{
  boot.loader.systemd-boot.enable = lib.mkDefault true;
  boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;

  boot.initrd.availableKernelModules = lib.mkDefault [
    "ahci"
    "nvme"
    "sd_mod"
    "sr_mod"
    "uas"
    "usb_storage"
    "usbhid"
    "xhci_pci"
  ];

  boot.supportedFilesystems = [
    "btrfs"
    "exfat"
    "ext4"
    "ntfs"
    "vfat"
  ];

  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/BOOT";
    fsType = "vfat";
  };

  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };
}
