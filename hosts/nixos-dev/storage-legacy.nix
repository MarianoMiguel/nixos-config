{
  boot.initrd.luks.devices = {
    "luks-f027bf34-a122-4d59-884f-abef07a04dd7".device =
      "/dev/disk/by-uuid/f027bf34-a122-4d59-884f-abef07a04dd7";
    "luks-c59b3968-6411-494d-b849-346ed55773e4".device =
      "/dev/disk/by-uuid/c59b3968-6411-494d-b849-346ed55773e4";
  };

  fileSystems."/" = {
    device = "/dev/mapper/luks-f027bf34-a122-4d59-884f-abef07a04dd7";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/628D-E942";
    fsType = "vfat";
    options = [
      "fmask=0077"
      "dmask=0077"
    ];
  };

  swapDevices = [
    { device = "/dev/mapper/luks-c59b3968-6411-494d-b849-346ed55773e4"; }
  ];
}
