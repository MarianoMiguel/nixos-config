{
  imports = [ ../nixos-dev/storage-legacy.nix ];

  boot.resumeDevice = "/dev/mapper/luks-c59b3968-6411-494d-b849-346ed55773e4";
}
