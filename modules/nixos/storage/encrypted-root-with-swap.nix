{ disko, ... }:

{
  imports = [ disko.nixosModules.disko ];

  disko.devices = {
    disk.main = {
      type = "disk";
      device = "/dev/disk/by-id/installer-selects-this-disk";
      content = {
        type = "gpt";
        partitions = {
          ESP = {
            label = "NIXOS-BOOT";
            size = "1G";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };
          luks = {
            label = "NIXOS-CRYPT";
            size = "100%";
            content = {
              type = "luks";
              name = "nixos-crypt";
              passwordFile = "/run/mariano-installer/luks-password";
              settings.allowDiscards = true;
              content = {
                type = "lvm_pv";
                vg = "nixos";
              };
            };
          };
        };
      };
    };

    lvm_vg.nixos = {
      type = "lvm_vg";
      lvs = {
        swap = {
          size = "64G";
          content = {
            type = "swap";
            resumeDevice = true;
          };
        };
        root = {
          size = "100%FREE";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
            mountOptions = [ "defaults" ];
          };
        };
      };
    };
  };
}
