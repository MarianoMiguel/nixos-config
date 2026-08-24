{
  fetchFromGitHub,
  kernel,
  kernelModuleMakeFlags,
  lib,
  stdenv,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "mt76-mt7925";
  version = "1.5.0";

  src = fetchFromGitHub {
    owner = "zbowling";
    repo = "mt7925";
    rev = "v${finalAttrs.version}";
    hash = "sha256-bqTPnSR2vIJhvdpb7VYv84exoOA7SHTTAxEuMytJjQ4=";
  };

  sourceRoot = "${finalAttrs.src.name}/dkms/src";

  hardeningDisable = [
    "format"
    "pic"
  ];
  nativeBuildInputs = kernel.moduleBuildDependencies;

  makeFlags = kernelModuleMakeFlags ++ [
    "KDIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
  ];

  installPhase = ''
    runHook preInstall

    moduleDir="$out/lib/modules/${kernel.modDirVersion}/updates"
    mkdir -p "$moduleDir"
    for module in ./*.ko; do
      install -Dm644 "$module" "$moduleDir/$(basename "$module")"
    done

    runHook postInstall
  '';

  meta = {
    description = "Patched out-of-tree mt76 modules for MT7921 and MT7925 Wi-Fi stability";
    homepage = "https://github.com/zbowling/mt7925";
    license = with lib.licenses; [
      gpl2Only
      isc
    ];
    platforms = lib.platforms.linux;
    broken = kernel.kernelOlder "6.17";
  };
})
