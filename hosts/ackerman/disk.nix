# ackerman's disk: LUKS2 on the GPT partition labelled "ackerman", btrfs inside with @, @home,
# @nix and @snapshots; the ESP (p4, label OMARCHY) holds the m1n1 payloads. macOS's APFS
# partitions are never touched. Key slots: 0 is Mariano's passphrase (typed at the Mac); one more
# holds a key kept on bonhart for unattended test reboots over the tether, to be removed once
# the Mac is settled (m5max-linux docs/nixos.md).
{
  boot.initrd.luks.devices.ackerman = {
    device = "/dev/disk/by-partlabel/ackerman";
    allowDiscards = true;
    bypassWorkqueues = true;
  };

  fileSystems =
    let
      btrfs = subvol: {
        device = "/dev/mapper/ackerman";
        fsType = "btrfs";
        options = [
          "subvol=${subvol}"
          "compress=zstd:1"
          "noatime"
        ];
      };
    in
    {
      "/" = btrfs "@";
      "/home" = btrfs "@home";
      "/nix" = btrfs "@nix";
      "/.snapshots" = btrfs "@snapshots";
      "/boot" = {
        device = "/dev/disk/by-label/OMARCHY";
        fsType = "vfat";
        options = [
          "noauto"
          "x-systemd.automount"
          "x-systemd.idle-timeout=120"
          "umask=0077"
          "nofail"
        ];
      };
    };

  zramSwap.enable = true;
  services.btrfs.autoScrub = {
    enable = true;
    fileSystems = [ "/" ];
  };

  # Hourly snapshots of /home (into /home/.snapshots, a subvolume made at install time); the
  # system itself rolls back through its generations.
  services.snapper.configs.home = {
    SUBVOLUME = "/home";
    ALLOW_USERS = [ "mariano" ];
    TIMELINE_CREATE = true;
    TIMELINE_CLEANUP = true;
    TIMELINE_LIMIT_HOURLY = 24;
    TIMELINE_LIMIT_DAILY = 7;
    TIMELINE_LIMIT_WEEKLY = 4;
    TIMELINE_LIMIT_MONTHLY = 0;
    TIMELINE_LIMIT_YEARLY = 0;
  };
}
