# ackerman's hardware: the J716C kernel and firmware from the private input, the boot arguments
# of the Arch daily, and an initrd that does what the bring-up's Alpine initramfs did: the USB
# gadget network to bonhart (usb0, 10.55.0.2), the NVMe (ANS) rebind, and the firmware the
# built-in drivers ask for before the root is open (trackpad, N1 Wi-Fi/Bluetooth). It adds the
# LUKS unlock: at the console (the internal keyboard), or over SSH on usb0, port 2222.
{
  config,
  lib,
  pkgs,
  ackerman-private,
  ...
}:

let
  priv = "${ackerman-private}/nixos";
  kernel = pkgs.callPackage ./packages/kernel.nix {
    # kernel-select.nix: the daily's tree, or j716c-next
    src = "${priv}/${if config.ackerman.kernel == "next" then "kernel-next" else "kernel"}";
    kernelPatches = [ ]; # not pkgs.kernelPatches, which callPackage would pass
  };

  # Apple's files for this board: the trackpad (MTP) firmware, the N1's FTAB and the camera's
  # sensor tuning (the IMX958 setfile, from this Mac's macOS 27.3)
  firmware = pkgs.runCommand "ackerman-firmware" { } ''
    install -Dm644 ${priv}/firmware/apple/tpmtfw-j716c.bin $out/lib/firmware/apple/tpmtfw-j716c.bin
    install -Dm644 ${priv}/firmware/apple/centauri/j716c-ftab.bin $out/lib/firmware/apple/centauri/j716c-ftab.bin
    install -Dm644 ${priv}/firmware/apple/isp_2224_01XX.dat $out/lib/firmware/apple/isp_2224_01XX.dat
  '';

  keys = import ./files/keys/authorized-keys.nix;

  # omarchy-m5's usb-gadget-net: every DWC3 UDC becomes a CDC-EEM gadget (bulk endpoints only;
  # NCM's interrupt endpoint stalls this port), usb<n> at 10.55.<n>.2. Idempotent: the gadget
  # the initrd made survives into stage 2.
  gadget = pkgs.writeShellScript "usb-gadget-net" ''
    # /bin last: in the initrd the store directories are absent and its /bin has these tools
    export PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.util-linux ]}:/bin
    CFG=/sys/kernel/config
    mountpoint -q $CFG || mount -t configfs none $CFG
    G=$CFG/usb_gadget
    [ -d $G/m5_0 ] && { echo "usb-gadget-net: the gadget is already up"; exit 0; }
    i=0
    while [ -z "$(ls /sys/class/udc 2>/dev/null)" ]; do
      i=$((i + 1)); [ $i -gt 300 ] && { echo "usb-gadget-net: no UDC"; exit 1; }
      sleep 0.1
    done
    n=0
    for udc in $(ls /sys/class/udc); do
      g=$G/m5_$n
      mkdir -p $g/strings/0x409 $g/configs/c.1/strings/0x409 $g/functions/eem.usb0
      echo 0x1d6b > $g/idVendor
      echo 0x0104 > $g/idProduct
      echo 0x0200 > $g/bcdUSB
      echo "omarchy-m5" > $g/strings/0x409/manufacturer
      echo "MBP16 M5 Max ackerman udc$n" > $g/strings/0x409/product
      echo "m5pro-$n" > $g/strings/0x409/serialnumber
      echo "eem" > $g/configs/c.1/strings/0x409/configuration
      echo 250 > $g/configs/c.1/MaxPower
      echo "02:4d:35:00:0$n:02" > $g/functions/eem.usb0/dev_addr
      ln -s $g/functions/eem.usb0 $g/configs/c.1/eem.usb0
      if echo "$udc" > $g/UDC; then
        echo "usb-gadget-net: udc=$udc gadget=m5_$n netdev=$(cat $g/functions/eem.usb0/ifname)"
      else
        echo "usb-gadget-net: binding $udc failed"
      fi
      n=$((n + 1))
    done
  '';

  # At the Mac, in the rescue: Mariano's passphrase into LUKS key slot 0, using the bonhart key
  # (copied to the initrd's RAM for this step only) to authorise it, then a test of what he typed
  setPassphrase = pkgs.writeShellScriptBin "ackerman-set-passphrase" ''
    # At the Mac, in the rescue: Mariano's passphrase into LUKS key slot 0, then the recovery
    # passphrase he writes down offline into slot 2 (slot 1 is the bonhart key, removed later).
    # The bonhart key, copied to the initrd's RAM for this step only, authorises both; each new
    # passphrase is tested once and re-set if the test fails; then the RAM copy is shredded.
    set -u
    CS=${pkgs.cryptsetup}/bin/cryptsetup
    DEV=/dev/disk/by-partlabel/ackerman KEY=/run/unattended.key
    [ -b $DEV ] && [ -s $KEY ] || { echo "needs $DEV and $KEY"; exit 1; }
    set_slot() {   # <slot> <what>
      for try in 1 2 3; do
        echo; echo "$2 (key slot $1). Type it twice:"
        $CS luksAddKey --key-slot $1 --key-file $KEY $DEV || { echo "not added, again"; continue; }
        echo "Now once more, to check it opens the disk:"
        if $CS open --test-passphrase --key-slot $1 $DEV; then echo "OK: slot $1 opens the disk"; return 0; fi
        echo "That didn't match: slot $1 is cleared, set it again."
        $CS luksKillSlot -q --key-file $KEY $DEV $1
      done
      echo "slot $1 not set after 3 tries"; return 1
    }
    set_slot 0 "1 of 2: your passphrase for ackerman's disk" || exit 1
    set_slot 2 "2 of 2: the recovery passphrase you write down offline" || exit 1
    ${pkgs.coreutils}/bin/shred -u $KEY && echo && echo "Done. The bonhart key is wiped from RAM."
  '';

  # T6050: the ANS (NVMe) firmware sometimes needs about 3 s to come up; a rebind of nvme-apple a
  # few seconds later succeeds. Every 12 s for a minute, until the disk appears.
  ansRebind = pkgs.writeShellScript "ans-rebind" ''
    export PATH=${lib.makeBinPath [ pkgs.coreutils pkgs.util-linux pkgs.gnugrep ]}:/bin
    NVME=45dcc0000.nvme DRV=/sys/bus/platform/drivers/nvme-apple
    for i in $(seq 1 60); do
      [ -b /dev/nvme0n1 ] && exit 0
      if [ $((i % 12)) -eq 0 ] && [ -d $DRV ] && dmesg | grep -q "ANS did not"; then
        echo "ans-rebind: ANS did not boot in time, rebinding $NVME"
        echo $NVME > $DRV/unbind 2>/dev/null; sleep 1; echo $NVME > $DRV/bind 2>/dev/null
      fi
      sleep 1
    done
  '';
in
{
  nixpkgs.hostPlatform = "aarch64-linux";

  boot.kernelPackages = pkgs.linuxPackagesFor kernel;
  # The toplevel's `kernel` is the gzipped Image the payload embeds (packages/ackerman-payload.py
  # wants one gzip member); aarch64's default is the plain Image, which this kernel doesn't ship
  # ("The bootloader cannot find the proper kernel image", 2026-11-08 21:39)
  system.boot.loader.kernelFile = "Image.gz";
  # The kernel has no CONFIG_FW_LOADER_COMPRESS: NixOS's default zstd-compressed firmware
  # (*.bin.zst) is invisible to it. The trackpad (tpmtfw-j716c.bin, dockchannel-hid) and the N1
  # (apple/centauri/j716c-ftab.bin, also in the initrd) failed with -2 on the first boot
  # (2026-11-08 21:57). Plain files until the kernel has FW_LOADER_COMPRESS_ZSTD.
  hardware.firmwareCompression = "none";
  # The bring-up's boot arguments (m5max-linux mk-payload.py BASE, the daily's; the battery
  # driver is on). m1n1 appends its own (idle=nop arm64.nowfxt); the payload adds init=.
  boot.kernelParams = [
    "earlycon=efifb"
    "keep_bootcon"
    "console=tty0"
    "pd_ignore_unused"
    "clk_ignore_unused"
    "no_console_suspend"
    "nvme_apple.flush_interval=0"
    "kvm-arm.wfi_trap_policy=trap"
    "pcie_aspm=off"
    # No SME for userspace. The M5 has SME/SME2 but no SVE, and Chrome 153's SME code paths start
    # with LLVM's prologue that saves VG with `cntd`, an SVE instruction that traps outside
    # streaming mode: every renderer that took one died with SIGILL (YouTube hung, 2026-11-08,
    # seven cores, `cntd x9` after `paciasp`). Without the hwcaps, Chrome and the like stay on their
    # NEON paths, and this kernel's untested SME context switching never runs.
    "arm64.nosme"
  ]
  # Route B for x86 programs (x86.nix): user4k=on lets a process tree run with 4K pages on this 16K
  # kernel (CONFIG_ARM64_USER4K_EXPERIMENTAL, Aurora's experimental per-process page sizes), which
  # FEX needs. The kernel has it built in and off; this turns it on for the boot (it costs 32 bytes
  # of page_ext per 16K page, about 0.2 % of RAM). It goes with ackerman.x86.enable: set that to
  # false and the next generation boots without it. Check after boot: the "4K userspace translation
  # granule" capability line in dmesg, and `userpages --status`.
  ++ lib.optional config.ackerman.x86.enable "user4k=on";
  boot.consoleLogLevel = 4;
  # The camera (apple_isp, /dev/v4l/by-path/platform-580000000.isp-video-index0, "FaceTime HD
  # Camera", NV12 1920x1080 and 1280x720) loads at boot since the device tree's soc@200000000 ranges
  # cover the ISP's capture-watchdog window (2026-11-13, aurora-silicon/linux#1854; m5max-linux
  # docs/camera.md). Idle, its power states are off; the decoder (avd) is not a capture device, so
  # apps list only the camera. Off for one boot: module_blacklist=apple_isp.

  hardware.deviceTree = {
    enable = true;
    name = "apple/t6050-j716c.dtb";
  };
  hardware.firmware = [ firmware ];
  hardware.enableRedistributableFirmware = false;

  # ---- initrd: systemd, everything built into the kernel, one gzip member (m1n1's rule)
  boot.initrd = {
    systemd.enable = true;
    compressor = "gzip";
    compressorArgs = [ "-9n" ];
    includeDefaultModules = false;
    availableKernelModules = lib.mkForce [ ];
    kernelModules = lib.mkForce [ ];

    # Programs only an ExecStart names are not pulled in by themselves (2026-11-08 20:24: the
    # rescue's usb-gadget-net failed at EXEC, ENOENT): list them
    systemd.storePaths = [
      gadget
      ansRebind
    ];

    # The built-in drivers' firmware, into the initrd's /lib (the modules closure)
    extraFirmwarePaths = [
      "apple/tpmtfw-j716c.bin"
      "apple/centauri/j716c-ftab.bin"
    ];

    systemd.services.usb-gadget-net = {
      description = "USB gadget network to bonhart (usb0)";
      wantedBy = [ "initrd.target" ];
      after = [ "systemd-udevd.service" ];
      before = [ "systemd-networkd.service" ];
      unitConfig.DefaultDependencies = false;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = gadget;
      };
    };
    systemd.services.ans-rebind = {
      description = "Rebind the NVMe (ANS) when its firmware is late";
      wantedBy = [ "initrd.target" ];
      after = [ "systemd-udevd.service" ];
      unitConfig.DefaultDependencies = false;
      serviceConfig = {
        Type = "simple";
        ExecStart = ansRebind;
      };
    };

    network.enable = true;
    # Keep usb0's address through switch-root: stage 2 sets the same one
    network.flushBeforeStage2 = false;
    systemd.network = {
      enable = true;
      networks."10-usb0" = {
        matchConfig.Name = "usb0";
        address = [ "10.55.0.2/24" ];
        linkConfig.RequiredForOnline = "no";
      };
    };
    # `ssh -p 2222 root@10.55.0.2 systemd-tty-ask-password-agent` answers the LUKS prompt; a plain
    # login gets a shell (the rescue, below)
    network.ssh = {
      enable = true;
      port = 2222;
      hostKeys = [ "/etc/secrets/initrd/ssh_host_ed25519_key" ];
      authorizedKeys = keys.bonhart;
    };

    # The rescue: this initrd, booted with rd.systemd.unit=ackerman-rescue.target (ackerman-payload
    # build --rescue), stops before any disk is opened, with the tether, SSH and a root shell on
    # the console, and the disk tools below. It is also where the disk is first partitioned.
    systemd.emergencyAccess = true;
    systemd.initrdBin = with pkgs; [
      btrfs-progs
      cryptsetup
      e2fsprogs
      gptfdisk
      util-linux
      gnused
      gnugrep
      setPassphrase
    ];
    # Not sysinit.target, which can pull in cryptsetup; the rescue payload also passes rd.luks=0.
    # Don't leave the console shell with `exit` (that resumes the normal boot): reboot instead.
    systemd.targets.ackerman-rescue = {
      description = "ackerman rescue (initrd): tether, SSH, a console shell, nothing opened";
      # initrd-nixos-copy-secrets puts the initrd SSH host key in place; only sysinit.target pulls
      # it in otherwise, so without it sshd exits at once (2026-11-08 20:24, and under QEMU)
      wants = [
        "systemd-udevd.service"
        "systemd-udev-trigger.service"
        "initrd-nixos-copy-secrets.service"
        "usb-gadget-net.service"
        "systemd-networkd.service"
        "sshd.service"
        "emergency.service"
      ];
      after = [ "systemd-udev-trigger.service" ];
      unitConfig.AllowIsolate = true;
    };
  };

  # The same gadget in stage 2, should the initrd's not be there
  systemd.services.usb-gadget-net = {
    description = "USB gadget network to bonhart (usb0)";
    wantedBy = [ "multi-user.target" ];
    before = [ "systemd-networkd.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = gadget;
    };
  };

  # The battery charge limit (Arch: battery-charge-limit.service): wheel may write the threshold
  systemd.services.battery-charge-limit = {
    description = "Let wheel set the battery charge limit, and restore the saved one";
    wantedBy = [ "multi-user.target" ];
    unitConfig.ConditionPathExists = "/sys/class/power_supply/macsmc-battery/charge_control_end_threshold";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      StateDirectory = "battery-charge-limit";
      StateDirectoryMode = "0775";
    };
    script = ''
      t=/sys/class/power_supply/macsmc-battery/charge_control_end_threshold
      chgrp wheel $t && chmod 0664 $t
      chgrp wheel /var/lib/battery-charge-limit
      [ -r /var/lib/battery-charge-limit/limit ] && cat /var/lib/battery-charge-limit/limit > $t || true
    '';
  };
}
