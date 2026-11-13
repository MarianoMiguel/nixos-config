# Aurora's camera noise filter on ackerman (Mariano, 2026-11-13: "let's get all the aurora stuff in").
# aurora-silicon/camera-denoise (MIT), packaged as aurora-silicon/nixos-aurora packages it
# (pkgs/camera-denoise.nix and modules/camera-denoise.nix). The commit is the one its sources.json
# pins; the codeload tarball matches its sha256 (055616e0...), and the hash below is that tarball's
# unpacked NAR hash (checked 2026-11-13).
# It is macOS's missing piece: macOS runs a temporal noise filter on every camera frame on the host,
# after the ISP. Aurora #774 measured flat-region noise of 13.6 on Linux,
# 2.1 on macOS and 2.4 through this filter (M4 Pro). m5max-linux docs/camera.md has the details.
#   - A PipeWire filter, run as a user service with each user's PipeWire. It adds a filtered camera
#     node that apps pick by default (portal, PipeWire, GStreamer); the raw camera stays as
#     "FaceTime HD Camera (V4L2)". Nothing runs until an app streams.
#   - Its board table has no J716C, so it runs the temporal filter on the CPU (NEON, about 3 ms of
#     one core per 1080p frame). The ANE and encoder (MCTF) backends aren't reachable on this kernel.
#   - Chrome uses the filtered camera only with its PipeWire camera feature, turned on below.
#     Without it, Chrome opens the raw V4L2 camera, as before.
#   - apple_isp.meta_exposure stays off: its gain read is unverified on T6050. The temporal filter
#     doesn't need it.
# Off by default since 2026-11-13 (Mariano, on the first generation with it: "camera actually feels
# worse now. still noisy in parts, but also kind of lowering the overall quality"). On this Mac it
# runs only its CPU fallback: moving areas restart their average and stay noisy, and the smoothing
# pass softens the rest. macOS does this on the video encoder's MCTF (and the Neural Engine in low
# light), which this kernel can't reach yet. Revisit when the encoder path works.
# On: ackerman.cameraDenoise.enable = true (the filter, and Chrome's flag).
# For one session: systemctl --user stop aurora-camera-denoise.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.ackerman.cameraDenoise;

  camera-denoise = pkgs.stdenv.mkDerivation {
    pname = "aurora-camera-denoise";
    version = "0.1.0";
    src = pkgs.fetchFromGitHub {
      owner = "aurora-silicon";
      repo = "camera-denoise";
      rev = "aa7a42ff3f26ac47c07b4cdb4ab1bfc5337291af";
      hash = "sha256-jOH0NYmkmlz7TtqaYw1fCaysoaAKoPh+8uyYhfs5RL0=";
    };
    nativeBuildInputs = with pkgs; [
      meson
      ninja
      pkg-config
    ];
    buildInputs = [ pkgs.pipewire ];
    mesonFlags = [
      "-Ddaemon=enabled"
      # The optional Vulkan temporal backend stays out, as in nixos-aurora, Fedora and Arch
      "-Dgpu=disabled"
      "-Dsysconfdir=/etc"
      "-Dsystemduserunitdir=${placeholder "out"}/lib/systemd/user"
    ];
    # Upstream's unit test: no unit for root or system users (the greeter), bounded restarts
    doCheck = true;
    postInstall = ''
      substituteInPlace $out/lib/systemd/user/aurora-camera-denoise.service \
        --replace-fail "ExecReload=/bin/kill" "ExecReload=${pkgs.coreutils}/bin/kill"
    '';
    meta = {
      description = "PipeWire filter that denoises the built-in camera in low light";
      homepage = "https://github.com/aurora-silicon/camera-denoise";
      license = lib.licenses.mit;
      mainProgram = "aurora-camera-denoise";
      platforms = [ "aarch64-linux" ];
    };
  };
in
{
  options.ackerman.cameraDenoise.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Aurora's camera noise filter, and Chrome's PipeWire camera feature to use it.";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ camera-denoise ];
    systemd.packages = [ camera-denoise ];
    systemd.user.services.aurora-camera-denoise.wantedBy = [ "pipewire.service" ];

    # Chrome's chrome://flags "PipeWire Camera support" (feature WebRtcPipeWireCamera). nixpkgs'
    # wrapper adds these arguments after its own Wayland ones; NIXOS_OZONE_WL isn't set on ackerman,
    # so this is the only --enable-features.
    nixpkgs.overlays = [
      (final: prev: {
        google-chrome = prev.google-chrome.override {
          commandLineArgs = "--enable-features=WebRtcPipeWireCamera";
        };
      })
    ];
  };
}
