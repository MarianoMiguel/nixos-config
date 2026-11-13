# Hardware video decoding on ackerman (Mariano, 2026-11-12): the T6050 video decoder (AVD), as
# Aurora's NixOS packages it (aurora-silicon/nixos-aurora 9713718d: avd-fw.nix,
# libva-v4l2-request-avd.nix; their docs/avd-vaapi.md).
#   - kernel: apple-avd.ko and the J716C decoder nodes come with the kernel from the private input
#     (from 7.3.0-ackerman-avd on); the driver loads apple/avd-fw-v5-t2.bin, the image aurora-silicon/
#     linux #1577 ran on the T6050 decoder;
#   - firmware: Aurora's open AVD firmware (aurora-silicon/avd-fw, MIT). It is ARM target code, so it is
#     built on bonhart as an x86_64 derivation and copied to the Mac (as x86.nix's closure is); the
#     build checks every image against Aurora's expected hashes;
#   - userspace: the VA-API driver (v4l2_request, also as aurora_drv_video.so for the GPU's render
#     node), in the graphics driver path, and vainfo. No global LIBVA_DRIVER_NAME.
# Browsers: stock Firefox decodes in software (its RDD sandbox blocks the media node; Aurora patches
# Firefox for that, not done here). mpv --hwdec=vaapi works as is.
# Off: ackerman.avd.enable = false, or for one boot module_blacklist=apple_avd.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.ackerman.avd;
  pkgsX86 = import pkgs.path {
    localSystem = "x86_64-linux";
    overlays = [ ];
  };

  # Source hashes: the NAR hashes of the codeload tarballs whose sha256 nixos-aurora pins (49a631c8...,
  # 826fda73...; checked 2026-11-12)
  avdFw = pkgsX86.callPackage ./packages/avd/avd-fw.nix {
    version = "0.1-unstable-2026-11-01.2";
    src = pkgsX86.fetchFromGitHub {
      owner = "aurora-silicon";
      repo = "avd-fw";
      rev = "6062e8516c0a751bc8e50f5d604a17395923189f";
      hash = "sha256-BvTSZR3qW6po3aWr5wvYMA0Lv8K18gYWHBR3CVSr3TE=";
    };
  };

  libvaAvd = pkgs.callPackage ./packages/avd/libva-v4l2-request-avd.nix {
    version = "1.3.r11";
    src = pkgs.fetchFromGitHub {
      owner = "omacom";
      repo = "libva-v4l2_request";
      rev = "4f60c51f7841dd74bb61c94a4ad31e630bbdab01";
      hash = "sha256-+M2XnhPP/vdNZqBZcQ1nk/EXZFHdDGPAbvF67AK1J5A=";
    };
    portabilityPatch = ./packages/avd/patches/libva-v4l2-request-offline-test-portability.patch;
    extraPatches = [
      ./packages/avd/patches/libva-v4l2-request-av1-chrome.patch
      ./packages/avd/patches/libva-v4l2-request-av1-multitile.patch
    ];
  };
in
{
  options.ackerman.avd.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Hardware video decoding: Aurora's AVD firmware, the VA-API driver and vainfo.";
  };

  config = lib.mkIf cfg.enable {
    hardware.firmware = [ avdFw ];
    hardware.graphics.extraPackages = [ libvaAvd ];
    environment.systemPackages = [ pkgs.libva-utils ];
    # On bonhart: nix build .#nixosConfigurations.ackerman.config.system.build.ackermanAvdFirmware,
    # then nix copy it to the Mac before the rebuild there
    system.build.ackermanAvdFirmware = avdFw;
  };
}
