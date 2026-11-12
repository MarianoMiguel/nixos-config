# Mesa for the M5 Max GPU: Aurora's agx3c branch at a8e86a80cdc4 plus aurora-silicon/mesa#185's
# one commit (G17C, the Max's four-cluster GPU), the tree the Arch daily runs from /opt/mesa-aurora
# (m5max-linux docs/gpu.md, E3). Only the Asahi drivers and the software fallbacks are built; GL
# runs on zink over the Asahi Vulkan driver (MESA_LOADER_DRIVER_OVERRIDE=zink in desktop.nix).
{
  lib,
  mesa,
  fetchFromGitHub,
  fetchpatch,
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
    version = "26.3.0-devel-agx3c-a8e86a80";

    src = fetchFromGitHub {
      owner = "aurora-silicon";
      repo = "mesa";
      rev = "a8e86a80cdc4695d00e7e63b8ebea263e557431b";
      hash = "sha256-awYcpEfIgZuF38kS7hBSVx9Afh5tszOBVc8CPdWVxL8=";
    };

    patches = [
      # aurora-silicon/mesa#185: hk keeps M5 command memory until its submissions complete
      (fetchpatch {
        url = "https://github.com/aurora-silicon/mesa/commit/f8d40b042cfbc4f54c671240131cf75b0ee54b75.patch";
        hash = "sha256-Cl8lFkgz98JcNAyX0vu13Hmw7UJ9X3Rs3hbhpre1qWQ=";
      })
    ];

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
