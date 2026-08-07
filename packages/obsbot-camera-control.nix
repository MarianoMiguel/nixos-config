{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  patchelf,
  qt6,
  libglvnd,
  lsof,
}:

stdenv.mkDerivation {
  pname = "obsbot-camera-control";
  version = "1.3.0-unstable-2026-04-13";

  src = fetchFromGitHub {
    owner = "aaronsb";
    repo = "obsbot-camera-control";
    rev = "5c2eb7dbafa2460803f6f875410b05524e692f8d";
    hash = "sha256-QzMJVsIwwRwTv3sVhQGdqgxqWSXIy2E3ylmeMqcdRm8=";
  };

  nativeBuildInputs = [
    cmake
    patchelf
    qt6.wrapQtAppsHook
  ];

  buildInputs = [
    libglvnd
    qt6.qtbase
    qt6.qtmultimedia
    stdenv.cc.cc.lib
  ];

  qtWrapperArgs = [
    "--prefix PATH : ${lib.makeBinPath [ lsof ]}"
  ];

  installPhase = ''
    runHook preInstall

    cd "$NIX_BUILD_TOP/$sourceRoot"

    install -Dm755 bin/obsbot-gui "$out/bin/obsbot-gui"
    install -Dm755 bin/obsbot-cli "$out/bin/obsbot-cli"

    install -Dm755 sdk/lib/libdev.so.1.0.2 "$out/lib/libdev.so.1.0.2"
    ln -s libdev.so.1.0.2 "$out/lib/libdev.so.1"
    ln -s libdev.so.1.0.2 "$out/lib/libdev.so"

    patchelf --set-rpath \
      "$out/lib:${lib.makeLibraryPath [ libglvnd qt6.qtbase qt6.qtmultimedia stdenv.cc.cc.lib ]}" \
      "$out/bin/obsbot-gui" "$out/bin/obsbot-cli"
    patchelf --set-rpath \
      "${lib.makeLibraryPath [ stdenv.cc.cc.lib ]}" \
      "$out/lib/libdev.so.1.0.2"

    install -Dm644 obsbot-control.desktop \
      "$out/share/applications/obsbot-control.desktop"
    install -Dm644 resources/icons/camera.svg \
      "$out/share/icons/hicolor/scalable/apps/obsbot-control.svg"
    install -Dm644 LICENSE \
      "$out/share/licenses/obsbot-camera-control/LICENSE"
    install -Dm644 README.md \
      "$out/share/doc/obsbot-camera-control/README.md"

    runHook postInstall
  '';

  meta = {
    description = "Native Linux control app for OBSBOT cameras";
    homepage = "https://github.com/aaronsb/obsbot-camera-control";
    # The application is MIT, but it bundles OBSBOT's unlicensed binary SDK.
    license = lib.licenses.unfree;
    mainProgram = "obsbot-gui";
    platforms = [ "x86_64-linux" ];
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
