# Mesa for the M5 Max GPU: aurora-silicon/mesa aurora-wip at 67df98cac686 (2026-11-12 22:20 UTC, the
# merge of #214). Besides everything before it, it has #185 (hk keeps M5 command memory until its
# submissions complete), #194 (native Gallium GL on G17S/G17C), #202-#206 (robustness; #205 admits
# the M5 Max without ASAHI_M5_BRINGUP), #207, #219, #239-#241 (Erik's M5 Max compute set), #256 and
# #258 (the two fixes for native GL in real apps: dword uniform ranges, without which Alacritty's text
# drew nothing; the narrowing move after the projective multiply, glmark2), and #257 (the M5 family's
# native programs cached per linked shader). Until 2026-11-12 this was agx3c a8e86a80cdc4 plus #185.
#
# The kernel ABI (checked offline against the wave kernel's header, 2026-11-12): aurora-wip's
# asahi_drm.h names the M5 commands differently from the kernel's (agx3c's header is the kernel's),
# but the layouts agree (clang record layouts): the kernel's 448-byte drm_asahi_cmd_render is
# aurora-wip's drm_asahi_cmd_render_with_ray_query, its 200-byte drm_asahi_cmd_compute is
# drm_asahi_cmd_compute_with_prior, and the shorter forms are prefixes the kernel zero-extends. The
# forms that would collide (stage prefixes v1, compute stage barriers: features 24/25) are never
# reported by the kernel (g17/mod.rs RETIRED_FEATURES), so this Mesa never sends them; GEM_USERPTR
# (#242) is appended to the ioctl list and gated on feature bit 37, which the kernel doesn't report;
# vm_create's HAL200 flag is optional. Aurora's distributions run the same pairing
# (integration/aurora's header is the wave kernel's).
#
# Only the Asahi drivers and the software fallbacks are built. GL is native (Gallium asahi) or zink
# over the Asahi Vulkan driver, chosen per session (ackerman.gl.driver in desktop.nix).
#
# The same file builds the x86_64 Mesa that x86 programs use under FEX (x86.nix): one source for
# both, as Aurora requires.
{
  lib,
  mesa,
  fetchFromGitHub,
}:

(mesa.override {
  galliumDrivers = [
    "asahi"
    "zink"
    "llvmpipe"
    "softpipe"
  ];
  vulkanDrivers = [ "asahi" ];
  vulkanLayers = [ ];
  eglPlatforms = [
    "x11"
    "wayland"
  ];
  enablePatentEncumberedCodecs = false;
}).overrideAttrs
  (old: {
    pname = "mesa-aurora";
    version = "26.3.0-devel-wip-67df98ca";

    src = fetchFromGitHub {
      owner = "aurora-silicon";
      repo = "mesa";
      rev = "67df98cac68658f9f9e4ba51b8fe1a2970ec05ea";
      hash = "sha256-YBx1q+kMA01QB/c9wynpo3t+zr1dyGRzWS6mbPaouao=";
    };

    # Everything it needs is merged; none of nixpkgs' patches apply to this tree (opencl.patch's
    # meson part is in postPatch below)
    patches = [ ];

    # nixpkgs checks that Mesa's GL headers match its separate mesa-gl-headers package; this
    # tree is newer than that package, so skip the check (the headers it removes stay removed).
    # nixpkgs' opencl.patch (dropped with its other patches by `patches` above) tells meson where
    # clang's libraries are: clang-unwrapped's lib, not LLVM's. Without it, "C++ shared or static
    # library 'clangBasic' not found" (2026-11-08 21:31). Its meson part, applied here.
    postPatch = ''
      patchShebangs .
      substituteInPlace meson.build --replace-fail \
        "llvm_libdir = dep_llvm.get_variable(cmake : 'LLVM_LIBRARY_DIR', configtool: 'libdir')" \
        "llvm_libdir = get_option('clang-libdir')"
      cat >> meson.options <<'EOF'

      option(
        'clang-libdir',
        type : 'string',
        value : ''',
        description : 'Locations to search for clang libraries.'
      )
      EOF
    '';

    # nixpkgs builds with meson's auto_features=enabled, which works for its driver set but not
    # this one: VA, XA and the like need drivers this build leaves out ("Feature gallium-va cannot
    # be enabled", 2026-11-08 21:29). So features are detected (auto), with the ones the Arch daily
    # enables (tools/gpu/build-mesa-aurora.sh) given explicitly below.
    mesonAutoFeatures = "auto";

    # No OpenCL (rusticl) and no Rust: the Asahi drivers don't need them. (clang-libdir stays: the
    # postPatch above adds the option; without it, "Unknown option: clang-libdir", 21:27.)
    mesonFlags =
      (lib.filter (
        f:
        !(lib.hasPrefix "-Dgallium-rusticl" f)
        && !(lib.hasPrefix "-Dteflon" f)
        && !(lib.hasPrefix "-Dintel-rt" f)
        && !(lib.hasPrefix "-Dtools" f)
      ) old.mesonFlags)
      ++ [
        (lib.mesonBool "gallium-rusticl" false)
        (lib.mesonBool "teflon" false)
        # Intel ray tracing needs the Intel Vulkan driver; the Panfrost tools aren't needed here
        (lib.mesonEnable "intel-rt" false)
        (lib.mesonOption "tools" "asahi")
        # As the Arch daily (build-mesa-aurora.sh)
        (lib.mesonEnable "egl" true)
        (lib.mesonEnable "gles1" true)
        (lib.mesonEnable "gles2" true)
        (lib.mesonOption "glx" "dri")
        (lib.mesonEnable "llvm" true)
        (lib.mesonEnable "expat" true)
        (lib.mesonEnable "zstd" true)
        (lib.mesonEnable "lmsensors" true)
        (lib.mesonOption "video-codecs" "")
      ];

    # Nix wants every output to exist; without the D3D12 drivers nothing goes to spirv2dxil
    # ("failed to produce output path for output 'spirv2dxil'", 2026-11-08 21:35)
    postInstall = (old.postInstall or "") + ''
      mkdir -p $spirv2dxil $opencl $cross_tools
    '';

    # nixpkgs' postFixup adds an RPATH to libRusticlOpenCL.so, which this build doesn't have.
    postFixup =
      builtins.replaceStrings [ " $opencl/lib/libRusticlOpenCL.so" ] [ "" ] old.postFixup;
  })
