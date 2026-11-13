# The bundle (2026-11-12; m5max-linux docs/status.md): with the private input's bundle kernel
# (7.3.0-ackerman-bundle: the wave's power management, the DCP at 120 Hz, zboot), its m1n1 stage-2
# with the DCP hand-off on, and the boot menu's entries.
#
# Switches for one boot are payload variants, not generations (ackerman-payload build TOP OUT
# --hold ...): the DCP off is `--no-chosen m5,t6050-display`, the PMP off is
# `--dtb TOP/dtbs/apple/t6050-j716c-nopmp.dtb`, the camera is `--chosen m5,t6050-isp=aura`.
{ ackerman-private, ... }:

{
  ackerman.payload = {
    # j716c-stage2-bundle (e8974977, 0x420000): n1warm-gpu plus the DCP pieces and Aura's camera
    # hand-off, both off unless their variable is set
    m1n1Name = "m1n1-stage2-bundle";
    chosen = [ "m5,t6050-display=1" ];
    # The PMP-off DTB until a PMP boot passes on this kernel (2026-11-12: the bundle kernel lacked the
    # PMP driver; the GPU waits on a running PMP)
    dtbName = "apple/t6050-j716c-nopmp.dtb";
  };

  # The entries for boot.bin.uboot, written beside the payload; boot.bin.uboot itself is never
  # boot.bin unless copied in by hand for a test (m5max-linux builds/private/uboot/README.md)
  ackerman.uboot = {
    enable = true;
    payload.uboot = "${ackerman-private}/nixos/uboot/u-boot-nodtb.bin.gz";
    payload.m1n1 = "${ackerman-private}/nixos/m1n1/m1n1-stage2-bundle.bin";
  };
}
