{ config, lib, ... }:

let
  installedStorage = builtins.pathExists ./storage.nix;
in
{
  imports = [
    ./common.nix
  ]
  ++ lib.optional installedStorage ./storage.nix
  # Bonhart was reinstalled with the guided installer's encrypted LVM layout.
  # A checkout outside /etc/nixos does not contain the ignored, machine-local
  # storage.nix, so its safe fallback must describe that current layout rather
  # than the obsolete pre-installer LUKS UUIDs.
  ++ lib.optional (!installedStorage) ./storage-encrypted.nix;

  assertions = lib.optional (!installedStorage) {
    assertion =
      builtins.hasAttr "nixos-crypt" config.boot.initrd.luks.devices
      && config.boot.initrd.luks.devices.nixos-crypt.device == "/dev/disk/by-partlabel/NIXOS-CRYPT"
      && config.fileSystems."/".device == "/dev/nixos/root"
      && config.boot.resumeDevice == "/dev/nixos/swap";
    message = "Bonhart's fallback storage must match its encrypted installer layout.";
  };
}
